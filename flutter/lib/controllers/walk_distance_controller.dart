import 'dart:async';

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

/// Hybrid walk distance: GPS while open, Health for closed gaps (PoGo-style).
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
  static const _keyClosedSince = '${_prefsPrefix}_closed_since';
  static const _keyBootstrapped = '${_prefsPrefix}_bootstrapped';
  static const _keyMode = '${_prefsPrefix}_mode_v3';
  /// Bumped when weekly seeding logic changes; triggers a one-time weekly reset.
  static const _keyWeeklySchema = '${_prefsPrefix}_weekly_schema';
  static const _weeklySchemaVersion = 1;

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
  DateTime? _closedSince;
  bool _bootstrappedFromHealth = false;
  ExploringDistanceMode _mode = ExploringDistanceMode.total;

  HealthDistancePermission _permission = HealthDistancePermission.unknown;
  DateTime? _lastSyncedAt;
  DateTime? _lastPersistAt;
  DateTime? _lastSyncAttemptAt;
  bool _loading = false;
  String? _error;
  Future<void>? _inFlightRefresh;
  /// Meters credited from Health for the most recent closed-app gap (consumed
  /// once by the profile-update callback for the visit XP badge).
  double? _pendingVisitGapMeters;
  /// Set when backgrounded while GPS is still covering distance (Explore in
  /// background). In-memory only — survives brief pause/resume, cleared on
  /// process death so a cold start can Health-credit the killed gap.
  bool _gpsCoveringClosedGap = false;

  double get activeMeters => _activeMeters;
  double get activeWeeklyMeters => _activeWeeklyMeters;
  double get totalMeters => _totalMeters;
  double get weeklyMeters => _weeklyMeters;
  ExploringDistanceMode get mode => _mode;
  HealthDistancePermission get permission => _permission;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get loading => _loading;
  String? get error => _error;

  /// Take and clear meters walked while the app was closed (for visit badge).
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
    // Always stamp so a later force-quit / cold start can Health-credit from
    // this moment. When GPS keeps running in background, resume clears the
    // stamp without crediting (see onAppResumed).
    _closedSince = DateTime.now();
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
      // Same process kept GPS warm — do not also credit Health for that window.
      _closedSince = null;
      _gpsCoveringClosedGap = false;
      await _persistLocal();
    } else if (!exploring) {
      _odometer.reset();
      _gpsCoveringClosedGap = false;
    }
    // Cold start after kill: _gpsCoveringClosedGap is false (memory cleared)
    // but _closedSince may still be in prefs → Health gap runs in refresh.
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

      // iOS HealthKit never discloses read grant status (hasPermissions →
      // null → unknown). Still attempt the gap read; empty/denied yields 0.
      if (status == HealthDistancePermission.granted ||
          status == HealthDistancePermission.unknown) {
        await _creditHealthGap(profile: profile);
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

  Future<void> _creditHealthGap({Profile? profile}) async {
    final now = DateTime.now();
    final closedSince = _closedSince;

    if (!_bootstrappedFromHealth &&
        _totalMeters <= 0 &&
        profile?.createdAt != null) {
      final seeded = await _health.distanceMeters(
        start: profile!.createdAt!,
        end: now,
      );
      if (seeded == null) {
        // Keep closedSince / bootstrap flag so a later resume can retry.
        return;
      }
      if (seeded > 0) {
        _totalMeters = seeded;
        final weekStart = localWeekStartMonday(now);
        final weekly = await _health.distanceMeters(start: weekStart, end: now);
        if (weekly != null) {
          _weeklyMeters = weekly;
        }
        _bootstrappedFromHealth = true;
        _closedSince = null;
        _permission = HealthDistancePermission.granted;
        return;
      }
    }

    if (closedSince == null) return;
    if (!now.isAfter(closedSince)) {
      _closedSince = null;
      return;
    }

    final gap = await _health.distanceMeters(start: closedSince, end: now);
    // Keep the stamp when the query fails so the next open can retry.
    if (gap == null) return;
    _closedSince = null;
    if (gap <= 0) return;

    _pendingVisitGapMeters = gap;
    _totalMeters += gap;
    final weekStart = localWeekStartMonday(now);
    if (!closedSince.isBefore(weekStart)) {
      _weeklyMeters += gap;
    } else if (now.isAfter(weekStart)) {
      final weekGap = await _health.distanceMeters(start: weekStart, end: now);
      if (weekGap != null && weekGap > 0) {
        _weeklyMeters += weekGap;
      }
    }
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
    final closed = prefs.getString(_keyClosedSince);
    if (closed != null) {
      _closedSince = DateTime.tryParse(closed);
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
    if (_closedSince != null) {
      await prefs.setString(
        _keyClosedSince,
        _closedSince!.toIso8601String(),
      );
    } else {
      await prefs.remove(_keyClosedSince);
    }
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
