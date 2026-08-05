import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/game_config.dart';
import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/gps_odometer.dart';
import '../services/health_distance_service.dart';
import '../services/location_service.dart';

/// Which exploration metrics the profile card should show.
enum ExploringDistanceMode {
  /// Speed-filtered GPS while the app was open (active exploration).
  active,

  /// Active + Health credits for closed-app gaps (total exploration).
  total,
}

/// Hybrid walk distance: GPS while open, Health weekly floor on resume.
///
/// Passive: `weekly = max(activeWeekly, Health(Monday→now))` so
/// passive ≈ Health − active. Health uses statistics queries (not raw sample
/// sums) to match the Health app when phone + watch both record.
class WalkDistanceController extends ChangeNotifier {
  WalkDistanceController({
    HealthDistanceService? healthService,
    ApiClient? apiClient,
    GpsOdometer? odometer,
  })  : _health = healthService ?? HealthDistanceService(),
        _api = apiClient ?? ApiClient.instance,
        _odometer = odometer ??
            GpsOdometer(
              maxSpeedMps: _maxDiscoverySpeedMps(),
            );

  static double _maxDiscoverySpeedMps() {
    try {
      final kmh =
          GameConfig.instance.siteDiscovery.discoveryMaxSpeedKmh;
      return kmh * 1000.0 / 3600.0;
    } catch (_) {
      return 5.56; // 20 km/h fallback before GameConfig.load
    }
  }

  /// Update the GPS speed filter when a tool buffs max discovery speed.
  void updateMaxDiscoverySpeedKmh(double kmh) {
    final mps = kmh * 1000.0 / 3600.0;
    if ((_odometer.maxSpeedMps - mps).abs() < 0.01) return;
    _odometer.maxSpeedMps = mps;
  }

  static const _prefsPrefix = 'walk_distance_v2';
  static const _keyActive = '${_prefsPrefix}_active_m';
  static const _keyActiveWeekly = '${_prefsPrefix}_active_weekly_m';
  static const _keyTotal = '${_prefsPrefix}_total_m';
  static const _keyWeekly = '${_prefsPrefix}_weekly_m';
  static const _keyWeekStart = '${_prefsPrefix}_week_start';
  /// Legacy gap stamp; migrated once into [_keyLastHealthAt].
  static const _keyClosedSince = '${_prefsPrefix}_closed_since';
  static const _keyLastHealthAt = '${_prefsPrefix}_last_health_at';
  static const _keyActiveAtLastHealth =
      '${_prefsPrefix}_active_at_last_health';
  static const _keyBootstrapped = '${_prefsPrefix}_bootstrapped';
  static const _keyMode = '${_prefsPrefix}_mode_v3';
  /// Bumped when weekly seeding logic changes; triggers a one-time weekly reset.
  static const _keyWeeklySchema = '${_prefsPrefix}_weekly_schema';
  static const _weeklySchemaVersion = 1;

  /// Health lookback cap (only last N days count).
  static const maxPassiveGap = Duration(days: 7);

  /// Below this, no visit badge (server also grants 0 XP below 10 m batches).
  static const minPassiveBadgeMeters = 10.0;

  final HealthDistanceService _health;
  final ApiClient _api;
  final GpsOdometer _odometer;

  LocationService? _location;
  VoidCallback? _locationListener;
  Future<void> Function(Profile profile)? _onProfileUpdated;
  bool _loaded = false;
  /// After a one-time weekly schema heal, push reset_weekly on the next sync.
  bool _pendingWeeklyReset = false;

  double _activeMeters = 0;
  double _activeWeeklyMeters = 0;
  double _totalMeters = 0;
  double _weeklyMeters = 0;
  String _weekStartIso = weekStartIso();
  DateTime? _lastHealthAt;
  double _activeAtLastHealth = 0;
  bool _bootstrappedFromHealth = false;
  ExploringDistanceMode _mode = ExploringDistanceMode.total;

  HealthDistancePermission _permission = HealthDistancePermission.unknown;
  DateTime? _lastSyncedAt;
  DateTime? _lastPersistAt;
  DateTime? _lastSyncAttemptAt;
  bool _loading = false;
  String? _error;
  Future<void>? _inFlightRefresh;
  /// Meters credited from Health on the most recent reconcile (consumed once
  /// by the profile-update callback for the visit XP badge).
  double? _pendingVisitGapMeters;
  /// Set when backgrounded while GPS is still covering distance (Explore in
  /// background). In-memory only — skip Health on same-process resume.
  bool _gpsCoveringClosedGap = false;
  /// When true, this resume/refresh should not run Health reconcile.
  bool _skipHealthReconcile = false;

  double get activeMeters => _activeMeters;
  double get activeWeeklyMeters => _activeWeeklyMeters;
  double get totalMeters => _totalMeters;
  double get weeklyMeters => _weeklyMeters;
  ExploringDistanceMode get mode => _mode;
  HealthDistancePermission get permission => _permission;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  DateTime? get lastHealthAt => _lastHealthAt;
  double get activeAtLastHealth => _activeAtLastHealth;
  bool get loading => _loading;
  String? get error => _error;

  /// Take and clear meters credited on the last Health reconcile (visit badge).
  double? takePendingVisitGapMeters() {
    final gap = _pendingVisitGapMeters;
    _pendingVisitGapMeters = null;
    return gap;
  }

  double get displayTotalMeters =>
      _mode == ExploringDistanceMode.active ? _activeMeters : _totalMeters;

  double get displayWeeklyMeters => _mode == ExploringDistanceMode.active
      ? _activeWeeklyMeters
      : _weeklyMeters;

  Future<void> bind(
    LocationService locationService, {
    Future<void> Function(Profile profile)? onProfileUpdated,
  }) async {
    _onProfileUpdated = onProfileUpdated;
    if (_location == locationService) return;
    await _ensureLoaded();
    notifyListeners();
    if (_location != null && _locationListener != null) {
      _location!.removeListener(_locationListener!);
    }
    _location = locationService;
    _locationListener ??= _onLocationChanged;
    _location!.addListener(_locationListener!);
  }

  Future<void> setMode(ExploringDistanceMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);
  }

  /// Seed lifetime totals from server profile when local counters are lower.
  ///
  /// Weekly counters are intentionally not seeded here: a Monday rollover that
  /// zeros local weekly would otherwise be undone by last week's profile
  /// totals (and a stale in-memory profile can re-poison after a heal).
  void applyProfile(Profile? profile) {
    if (profile == null) return;
    var changed = false;
    if (profile.totalDistanceM > _totalMeters) {
      _totalMeters = profile.totalDistanceM;
      changed = true;
    }
    if (profile.activeDistanceM > _activeMeters) {
      _activeMeters = profile.activeDistanceM;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(_persistLocal());
    }
  }

  Future<void> onAppBackgrounded() async {
    final exploring = _location?.isBackgroundExploring ?? false;
    if (exploring) {
      _gpsCoveringClosedGap = true;
      await _persistLocal();
      await _syncToBackend(force: true);
      return;
    }
    _gpsCoveringClosedGap = false;
    _odometer.reset();
    await _persistLocal();
    await _syncToBackend(force: true);
  }

  Future<void> onAppResumed({Profile? profile}) async {
    final exploring = _location?.isBackgroundExploring ?? false;
    if (exploring && _gpsCoveringClosedGap) {
      // Same process kept GPS warm — skip Health this time; weekly already
      // includes GPS meters so a later floor reconcile will not double-count.
      _gpsCoveringClosedGap = false;
      _skipHealthReconcile = true;
    } else if (!exploring) {
      _odometer.reset();
      _gpsCoveringClosedGap = false;
      _skipHealthReconcile = false;
    } else {
      // Cold start with BG explore enabled: GPS was not covering after kill.
      _skipHealthReconcile = false;
    }
    await refresh(
      profile: profile,
      requestPermissionIfNeeded: false,
    );
  }

  Future<void> refresh({
    required Profile? profile,
    bool requestPermissionIfNeeded = false,
    bool force = false,
  }) {
    final existing = _inFlightRefresh;
    if (existing != null) return existing;
    final future = _refresh(
      profile: profile,
      requestPermissionIfNeeded: requestPermissionIfNeeded,
      force: force,
    );
    _inFlightRefresh = future.whenComplete(() => _inFlightRefresh = null);
    return _inFlightRefresh!;
  }

  Future<void> _refresh({
    required Profile? profile,
    required bool requestPermissionIfNeeded,
    required bool force,
  }) async {
    await _ensureLoaded();
    _rolloverWeekIfNeeded();
    if (profile != null) applyProfile(profile);

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      var status = await _health.checkPermission();
      if (status != HealthDistancePermission.granted &&
          requestPermissionIfNeeded &&
          status != HealthDistancePermission.unsupported) {
        final granted = await _health.requestAuthorization();
        status = granted
            ? HealthDistancePermission.granted
            : (status == HealthDistancePermission.unavailable
                ? status
                : HealthDistancePermission.denied);
      }
      _permission = status;

      final skip = _skipHealthReconcile;
      _skipHealthReconcile = false;

      // iOS HealthKit never discloses read grant status (hasPermissions →
      // null → unknown). Still attempt the read; empty/denied yields 0.
      if (!skip &&
          (status == HealthDistancePermission.granted ||
              status == HealthDistancePermission.unknown)) {
        await _reconcileHealthPassive();
      }

      await _persistLocal();
      await _syncToBackend(force: force);
    } catch (error) {
      _error = error.toString();
      if (kDebugMode) {
        debugPrint('WalkDistanceController.refresh: $error');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _onLocationChanged() {
    final location = _location;
    if (location == null) return;
    final allow = location.isAppForeground || location.isBackgroundExploring;
    if (!allow) return;
    final position = location.lastPosition;
    if (position == null) return;
    unawaited(_ingestPosition(position));
  }

  Future<void> _ingestPosition(Position position) async {
    await _ensureLoaded();
    _rolloverWeekIfNeeded();

    final accuracy = position.accuracy;
    final speed = position.speed;
    final result = _odometer.addFix(
      GpsFix(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
        accuracyMeters: accuracy.isFinite ? accuracy : null,
        speedMps: speed.isFinite && speed >= 0 ? speed : null,
      ),
    );
    if (!result.accepted || result.acceptedMeters <= 0) return;

    final meters = result.acceptedMeters;
    _activeMeters += meters;
    _activeWeeklyMeters += meters;
    _totalMeters += meters;
    _weeklyMeters += meters;
    notifyListeners();

    final now = DateTime.now();
    if (_lastPersistAt == null ||
        now.difference(_lastPersistAt!) > const Duration(seconds: 5)) {
      _lastPersistAt = now;
      await _persistLocal();
    }
    if (_lastSyncAttemptAt == null ||
        now.difference(_lastSyncAttemptAt!) > const Duration(seconds: 30)) {
      await _syncToBackend();
    }
  }

  /// Align weekly total with Health: `weekly = max(activeWeekly, Health(week))`.
  ///
  /// Passive this week = Health − active (floored at 0). Raises or heals weekly
  /// when a prior reconcile over-counted; uses [reset_weekly] on sync when
  /// lowering. Lifetime total moves by the same delta (clamped ≥ active).
  Future<void> _reconcileHealthPassive() async {
    final now = DateTime.now();
    final weekStart = localWeekStartMonday(now);
    final earliest = now.subtract(maxPassiveGap);
    // Never look back more than 7 days (and not before this Monday).
    final start = weekStart.isBefore(earliest) ? earliest : weekStart;
    if (!now.isAfter(start)) return;

    final health = await _health.distanceMeters(start: start, end: now);
    if (health == null) return;

    // User model: passive = Health − active; weekly total = active + passive.
    final targetWeekly = math.max(_activeWeeklyMeters, health);
    final delta = targetWeekly - _weeklyMeters;
    if (delta.abs() < 0.5) {
      _lastHealthAt = now;
      _activeAtLastHealth = _activeMeters;
      _bootstrappedFromHealth = true;
      _permission = HealthDistancePermission.granted;
      return;
    }

    _weeklyMeters = targetWeekly;
    _totalMeters = math.max(_activeMeters, _totalMeters + delta);
    if (delta < 0) {
      // Heal an over-credit; force server to take the corrected weekly.
      _pendingWeeklyReset = true;
    }
    if (delta >= minPassiveBadgeMeters) {
      _pendingVisitGapMeters = delta;
    }

    _lastHealthAt = now;
    _activeAtLastHealth = _activeMeters;
    _bootstrappedFromHealth = true;
    _permission = HealthDistancePermission.granted;
  }

  void _rolloverWeekIfNeeded() {
    final current = weekStartIso();
    if (current == _weekStartIso) return;
    _weekStartIso = current;
    _activeWeeklyMeters = 0;
    _weeklyMeters = 0;
    // Ensure server accepts the fresh window even if a prior buggy sync already
    // wrote last week's totals under this Monday.
    _pendingWeeklyReset = true;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _activeMeters = prefs.getDouble(_keyActive) ?? 0;
    _activeWeeklyMeters = prefs.getDouble(_keyActiveWeekly) ?? 0;
    _totalMeters = prefs.getDouble(_keyTotal) ?? 0;
    _weeklyMeters = prefs.getDouble(_keyWeekly) ?? 0;
    _weekStartIso = prefs.getString(_keyWeekStart) ?? weekStartIso();
    _bootstrappedFromHealth = prefs.getBool(_keyBootstrapped) ?? false;
    _activeAtLastHealth =
        prefs.getDouble(_keyActiveAtLastHealth) ?? _activeMeters;

    final lastHealth = prefs.getString(_keyLastHealthAt);
    if (lastHealth != null) {
      _lastHealthAt = DateTime.tryParse(lastHealth);
    }

    // One-time migrate: old closed_since → lastHealthAt watermark.
    final closed = prefs.getString(_keyClosedSince);
    if (_lastHealthAt == null && closed != null) {
      _lastHealthAt = DateTime.tryParse(closed);
      _activeAtLastHealth = _activeMeters;
      await prefs.remove(_keyClosedSince);
    } else if (closed != null) {
      await prefs.remove(_keyClosedSince);
    }

    final modeName = prefs.getString(_keyMode);
    if (modeName == ExploringDistanceMode.active.name) {
      _mode = ExploringDistanceMode.active;
    } else {
      // Default (and any unknown value): Total exploration, checkbox checked.
      _mode = ExploringDistanceMode.total;
    }
    if (modeName == null) {
      await prefs.setString(_keyMode, ExploringDistanceMode.total.name);
    }
    _rolloverWeekIfNeeded();
    // One-shot heal: older builds re-seeded last week's weekly under the new
    // Monday via applyProfile, so "this week" never reset. Clear weekly once.
    final schema = prefs.getInt(_keyWeeklySchema) ?? 0;
    if (schema < _weeklySchemaVersion) {
      _activeWeeklyMeters = 0;
      _weeklyMeters = 0;
      _weekStartIso = weekStartIso();
      _pendingWeeklyReset = true;
      await prefs.setInt(_keyWeeklySchema, _weeklySchemaVersion);
      await _persistLocal();
    }
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyActive, _activeMeters);
    await prefs.setDouble(_keyActiveWeekly, _activeWeeklyMeters);
    await prefs.setDouble(_keyTotal, _totalMeters);
    await prefs.setDouble(_keyWeekly, _weeklyMeters);
    await prefs.setString(_keyWeekStart, _weekStartIso);
    await prefs.setBool(_keyBootstrapped, _bootstrappedFromHealth);
    await prefs.setDouble(_keyActiveAtLastHealth, _activeAtLastHealth);
    if (_lastHealthAt != null) {
      await prefs.setString(
        _keyLastHealthAt,
        _lastHealthAt!.toIso8601String(),
      );
    } else {
      await prefs.remove(_keyLastHealthAt);
    }
    // Legacy key should stay gone after migrate.
    await prefs.remove(_keyClosedSince);
  }

  Future<void> _syncToBackend({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastSyncAttemptAt != null &&
        now.difference(_lastSyncAttemptAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastSyncAttemptAt = now;
    final resetWeekly = _pendingWeeklyReset;
    try {
      final response = await _api.patch(
        '/api/v1/users/me/distance',
        body: {
          'total_distance_m': _totalMeters,
          'weekly_distance_m': _weeklyMeters,
          'active_distance_m': _activeMeters,
          'active_weekly_distance_m': _activeWeeklyMeters,
          'week_start': _weekStartIso,
          if (resetWeekly) 'reset_weekly': true,
        },
      );
      _lastSyncedAt = DateTime.now();
      _pendingWeeklyReset = false;
      final serverTotal = (response['total_distance_m'] as num?)?.toDouble();
      final serverWeekly = (response['weekly_distance_m'] as num?)?.toDouble();
      final serverActive = (response['active_distance_m'] as num?)?.toDouble();
      final serverActiveWeekly =
          (response['active_weekly_distance_m'] as num?)?.toDouble();
      if (serverTotal != null) _totalMeters = serverTotal;
      if (serverWeekly != null) _weeklyMeters = serverWeekly;
      if (serverActive != null) _activeMeters = serverActive;
      if (serverActiveWeekly != null) {
        _activeWeeklyMeters = serverActiveWeekly;
      }
      await _persistLocal();
      notifyListeners();

      // Distance sync returns a full profile (may include walk XP awards).
      try {
        final profile = Profile.fromJson(response);
        final onUpdated = _onProfileUpdated;
        if (onUpdated != null) {
          await onUpdated(profile);
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('WalkDistanceController.profile: $error');
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('WalkDistanceController.sync: $error');
      }
    }
  }

  @override
  void dispose() {
    if (_location != null && _locationListener != null) {
      _location!.removeListener(_locationListener!);
    }
    super.dispose();
  }
}
