import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/game_config.dart';
import '../../../../config/main_param_resolve.dart';
import '../../../../models/profile.dart';
import '../../../../models/site.dart';
import '../../../../services/api_client.dart';
import '../../../../services/location_service.dart';
import '../../../../utils/discovery_haptic.dart';
import '../../domain/site_dimension_display.dart';

/// Accrues time-based documentation while identified sites are in range.
class SiteExplorationController extends ChangeNotifier {
  SiteExplorationController({
    ApiClient? apiClient,
    DateTime Function()? now,
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> body,
    )?
    patchRequest,
  }) : _api = apiClient ?? ApiClient.instance,
       _now = now ?? DateTime.now,
       _patchRequest = patchRequest;

  static const _prefsKey = 'site_documentation_v2';
  static const _legacyPrefsKey = 'site_exploration_v1';
  static const _syncInterval = Duration(seconds: 30);

  final ApiClient _api;
  final DateTime Function() _now;
  final Future<Map<String, dynamic>> Function(
    String path,
    Map<String, dynamic> body,
  )?
  _patchRequest;

  LocationService? _location;
  VoidCallback? _locationListener;
  List<SiteSummary> Function()? _discoveredSitesProvider;
  int Function()? _skillLevelProvider;
  Future<void> Function(Profile profile)? _onProfileUpdated;
  void Function(SiteSummary site)? _onSiteUpdated;

  /// Local unit-interval documentation contribution by site id (monotonic).
  final Map<int, double> _progressBySite = {};
  final Set<int> _documentedSiteIds = {};
  final Set<int> _dirtySiteIds = {};
  final Set<int> _sitesInRange = {};
  DateTime? _lastSyncAttemptAt;
  DateTime? _lastVerifiedAt;
  DateTime? _lastTickAt;
  DateTime? _lastHandledLocationFixAt;
  Position? _lastVerifiedPosition;
  Timer? _tickTimer;
  bool _syncInFlight = false;
  bool _appForeground = true;
  bool _loaded = false;

  /// FIFO of documentation celebrations (keeps each site separate).
  final List<SiteSummary> _documentationCelebrationQueue = [];

  Map<int, double> get progressBySite => Map.unmodifiable(_progressBySite);

  bool isDocumented(int siteId) => _documentedSiteIds.contains(siteId);

  SiteSummary? get pendingDocumentationCelebration =>
      _documentationCelebrationQueue.isEmpty
      ? null
      : _documentationCelebrationQueue.first;

  int get pendingDocumentationCelebrationCount =>
      _documentationCelebrationQueue.length;

  /// Snapshot of documentation celebrations waiting (oldest first).
  List<SiteSummary> get documentationCelebrationQueue =>
      List.unmodifiable(_documentationCelebrationQueue);

  void consumeDocumentationCelebration() {
    if (_documentationCelebrationQueue.isEmpty) return;
    _documentationCelebrationQueue.removeAt(0);
    notifyListeners();
  }

  /// Best-known documentation progress for [siteId].
  double documentationProgressFor(int siteId, {double fallback = 0.0}) {
    final local = _progressBySite[siteId];
    if (local == null) return fallback;
    if (_documentedSiteIds.contains(siteId)) {
      return local;
    }
    return local > fallback ? local : fallback;
  }

  bool isInDocumentationRange(int siteId) => _sitesInRange.contains(siteId);

  double? _documentationDistanceMOverride;
  double? _discoverySpeedOverride;

  double get documentationDistanceM {
    final override = _documentationDistanceMOverride;
    if (override != null) {
      return override;
    }
    try {
      if (!GameConfig.isLoaded) return 50.0;
      return GameConfig
          .instance
          .siteStewardship
          .mainParams
          .documentationDistanceM;
    } catch (_) {
      return 50.0;
    }
  }

  void updateSiteVisibilityM(double meters) {
    if (_documentationDistanceMOverride != null &&
        (_documentationDistanceMOverride! - meters).abs() < 0.01) {
      return;
    }
    _documentationDistanceMOverride = meters;
  }

  double get discoverySpeed {
    final override = _discoverySpeedOverride;
    if (override != null) return override;
    try {
      if (!GameConfig.isLoaded) return 0.01;
      return GameConfig.instance.siteStewardship.mainParams.discoverySpeed;
    } catch (_) {
      return 0.01;
    }
  }

  void updateDiscoverySpeed(double value) {
    final next = value.clamp(0.0, double.infinity);
    if (_discoverySpeedOverride != null &&
        (_discoverySpeedOverride! - next).abs() < 1e-9) {
      return;
    }
    _discoverySpeedOverride = next;
  }

  @visibleForTesting
  Future<void> debugInitializeForTest({
    required List<SiteSummary> Function() discoveredSitesProvider,
    int Function()? skillLevelProvider,
  }) async {
    _discoveredSitesProvider = discoveredSitesProvider;
    _skillLevelProvider = skillLevelProvider;
    await _loadLocal();
  }

  @visibleForTesting
  Future<void> debugCreditElapsed({
    required Position position,
    required Duration elapsed,
    Position? startPosition,
  }) {
    _refreshSitesInRange(position);
    return _creditElapsed(
      position,
      elapsed,
      startPosition: startPosition,
      sync: false,
    );
  }

  @visibleForTesting
  Future<void> debugSync() => _syncToBackend(force: true);

  Future<void> bind(
    LocationService location, {
    required List<SiteSummary> Function() discoveredSitesProvider,
    int Function()? skillLevelProvider,
    Future<void> Function(Profile profile)? onProfileUpdated,
    void Function(SiteSummary site)? onSiteUpdated,
  }) async {
    _discoveredSitesProvider = discoveredSitesProvider;
    _skillLevelProvider = skillLevelProvider;
    _onProfileUpdated = onProfileUpdated;
    _onSiteUpdated = onSiteUpdated;
    if (_location != null) return;
    await _loadLocal();
    // One-shot sync so backend can complete already-ready sites.
    for (final id in _progressBySite.keys) {
      if (!_documentedSiteIds.contains(id)) {
        _dirtySiteIds.add(id);
      }
    }
    _location = location;
    _locationListener = _handleLocationChanged;
    location.addListener(_locationListener!);
    _lastVerifiedPosition = location.lastPosition;
    _lastVerifiedAt = _now();
    _lastTickAt = _lastVerifiedAt;
    _lastHandledLocationFixAt = location.lastPositionAt;
    _tickTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_onTick()),
    );
    _refreshSitesInRange(location.lastPosition);
    if (_dirtySiteIds.isNotEmpty) {
      unawaited(_syncToBackend(force: true));
    }
  }

  /// Seed / raise local counters from server site summaries.
  ///
  /// Server is authoritative when the viewer has no discoverer progress or
  /// when local is not dirty and behind.
  void ingestSites(Iterable<SiteSummary> sites) {
    var changed = false;
    for (final site in sites) {
      final server = site.documentationProgress;
      if (server == null) {
        // No discoverer link / progress for viewer — drop stale local buffer.
        if (_progressBySite.remove(site.siteId) != null) changed = true;
        if (_documentedSiteIds.remove(site.siteId)) changed = true;
        _dirtySiteIds.remove(site.siteId);
        continue;
      }

      if (site.documented == true) {
        if (_documentedSiteIds.add(site.siteId)) changed = true;
        if ((_progressBySite[site.siteId] ?? -1) != server) {
          _progressBySite[site.siteId] = server;
          changed = true;
        }
        continue;
      }

      if (_documentedSiteIds.remove(site.siteId)) changed = true;
      final local = _progressBySite[site.siteId];
      final dirty = _dirtySiteIds.contains(site.siteId);
      if (local == null || server > local || (!dirty && server < local)) {
        if (local != server) {
          _progressBySite[site.siteId] = server;
          changed = true;
        }
      }
    }
    if (changed) {
      unawaited(_persistLocal());
      notifyListeners();
    }
  }

  /// Wipe local exploration / documentation progress (e.g. after admin purge).
  Future<void> clearAllProgress() async {
    if (_progressBySite.isEmpty &&
        _documentedSiteIds.isEmpty &&
        _dirtySiteIds.isEmpty &&
        _documentationCelebrationQueue.isEmpty) {
      return;
    }
    _progressBySite.clear();
    _documentedSiteIds.clear();
    _dirtySiteIds.clear();
    _documentationCelebrationQueue.clear();
    await _persistLocal();
    notifyListeners();
  }

  void onAppResumed() {
    _appForeground = true;
    _lastTickAt = _now();
    _lastVerifiedAt = _lastTickAt;
    _lastVerifiedPosition = _location?.lastPosition;
    _lastHandledLocationFixAt = _location?.lastPositionAt;
    _refreshSitesInRange(_location?.lastPosition);
  }

  Future<void> onAppBackgrounded() async {
    _appForeground = false;
    _lastTickAt = _now();
    _lastVerifiedAt = _lastTickAt;
    _lastVerifiedPosition = _location?.lastPosition;
    await _syncToBackend(force: true);
  }

  Future<void> _loadLocal() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_prefsKey);
      var migrateLegacy = false;
      if (raw == null || raw.isEmpty) {
        raw = prefs.getString(_legacyPrefsKey);
        migrateLegacy = raw != null && raw.isNotEmpty;
      }
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        final value = (entry.value as num?)?.toDouble();
        if (id == null || value == null) continue;
        _progressBySite[id] = (migrateLegacy ? value * 0.01 : value).clamp(
          0.0,
          1.0,
        );
      }
      if (migrateLegacy) await _persistLocal();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SiteExplorationController.load: $error');
      }
    }
  }

  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = {
        for (final e in _progressBySite.entries) '${e.key}': e.value,
      };
      await prefs.setString(_prefsKey, jsonEncode(encoded));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SiteExplorationController.persist: $error');
      }
    }
  }

  bool _isEligible(SiteSummary site) {
    if (site.latitude == null || site.longitude == null) return false;
    if (site.discoveredAt == null &&
        (site.status == null || site.status == 'hidden')) {
      return false;
    }
    if (site.needsIdentification) return false;
    return site.documented != true && !_documentedSiteIds.contains(site.siteId);
  }

  bool _isWithin(Position position, SiteSummary site) {
    return Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          site.latitude!,
          site.longitude!,
        ) <=
        documentationDistanceM;
  }

  void _refreshSitesInRange(Position? position) {
    final next = <int>{};
    if (position != null) {
      for (final site
          in _discoveredSitesProvider?.call() ?? const <SiteSummary>[]) {
        if (_isEligible(site) && _isWithin(position, site)) {
          next.add(site.siteId);
        }
      }
    }
    if (setEquals(next, _sitesInRange)) return;
    _sitesInRange
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void _handleLocationChanged() {
    final location = _location;
    final position = location?.lastPosition;
    if (location == null || position == null) return;
    final fixAt = location.lastPositionAt;
    if (fixAt == null || fixAt == _lastHandledLocationFixAt) {
      _refreshSitesInRange(position);
      return;
    }
    _lastHandledLocationFixAt = fixAt;
    final now = _now();
    if (!_appForeground && location.isBackgroundExploring) {
      final previousAt = _lastVerifiedAt;
      final previousPosition = _lastVerifiedPosition;
      if (previousAt != null &&
          previousPosition != null &&
          now.isAfter(previousAt)) {
        unawaited(
          _creditElapsed(
            position,
            now.difference(previousAt),
            startPosition: previousPosition,
          ),
        );
      }
    }
    _lastVerifiedAt = now;
    _lastVerifiedPosition = position;
    _refreshSitesInRange(position);
  }

  Future<void> _onTick() async {
    final now = _now();
    final previous = _lastTickAt ?? now;
    _lastTickAt = now;
    if (!_appForeground) return;
    final position = _location?.lastPosition;
    if (position == null || !now.isAfter(previous)) return;
    _refreshSitesInRange(position);
    final elapsed = now.difference(previous);
    // A delayed foreground timer must not turn an app suspension into offline
    // documentation credit.
    final verified = elapsed > const Duration(seconds: 2)
        ? const Duration(seconds: 2)
        : elapsed;
    await _creditElapsed(position, verified);
  }

  Future<void> _creditElapsed(
    Position position,
    Duration elapsed, {
    Position? startPosition,
    bool sync = true,
  }) async {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0 || discoverySpeed <= 0) return;
    final sites = _discoveredSitesProvider?.call() ?? const <SiteSummary>[];
    if (sites.isEmpty) return;
    final skillLevel = _skillLevelProvider?.call() ?? 1;
    var credited = false;
    var documentationReady = false;
    for (final site in sites) {
      if (!_isEligible(site) || !_isWithin(position, site)) continue;
      if (startPosition != null && !_isWithin(startPosition, site)) continue;
      final previous =
          _progressBySite[site.siteId] ?? site.documentationProgress ?? 0.0;
      final next = (previous + seconds * discoverySpeed).clamp(0.0, 1.0);
      if (next <= previous) continue;
      _progressBySite[site.siteId] = next;
      _dirtySiteIds.add(site.siteId);
      credited = true;
      if (_isLocallyComplete(site, skillLevel: skillLevel, progress: next)) {
        documentationReady = true;
      }
    }
    if (!credited) return;
    await _persistLocal();
    notifyListeners();
    // Force sync as soon as local progress completes documentation so
    // celebration / XP / status don't wait on the 30s interval.
    if (sync) {
      unawaited(_syncToBackend(force: documentationReady));
    }
  }

  bool _isLocallyComplete(
    SiteSummary site, {
    required int skillLevel,
    required double progress,
  }) {
    final bands = <SiteDimensionKey, SiteDimensionBand?>{
      SiteDimensionKey.dino: site.oddDinoBand,
      SiteDimensionKey.fossil: site.oddFossilBand,
      SiteDimensionKey.completeness: site.oddCompletenessBand,
      SiteDimensionKey.quality: site.oddQualityBand,
      SiteDimensionKey.depth: site.oddDepthBand,
    };
    final exactValues = <SiteDimensionKey, double?>{
      SiteDimensionKey.dino: site.oddDinoCount,
      SiteDimensionKey.fossil: site.oddFossilCount,
      SiteDimensionKey.completeness: site.oddCompleteness,
      SiteDimensionKey.quality: site.oddQuality,
      SiteDimensionKey.depth: site.oddDepth,
    };
    final base =
        resolveSiteStewardshipAccuracies(
          skillLevel: skillLevel,
        )['documentation_accuracy'] ??
        0.0;
    for (final dimension in SiteDimensionKey.values) {
      final band = bands[dimension];
      if (band == null && exactValues[dimension] == null) return false;
      final localAccuracy = applyDocumentationProgress(
        applyDimensionAccuracyNoise(
          baseAccuracy: base,
          siteId: site.siteId,
          dimension: dimension,
        ),
        progress,
      );
      final effective = math.max(localAccuracy, band?.effectiveAccuracy ?? 0.0);
      if (effective < 1.0 - 1e-9) return false;
    }
    return true;
  }

  Future<void> _syncToBackend({bool force = false}) async {
    final now = _now();
    if (!force &&
        _lastSyncAttemptAt != null &&
        now.difference(_lastSyncAttemptAt!) < _syncInterval) {
      return;
    }
    if (_dirtySiteIds.isEmpty || _syncInFlight) return;
    _lastSyncAttemptAt = now;
    _syncInFlight = true;

    final toSync = _dirtySiteIds.toList();
    final reportedProgress = <int, double>{
      for (final siteId in toSync)
        if (_progressBySite.containsKey(siteId))
          siteId: _progressBySite[siteId]!,
    };
    final body = {
      'sites': [
        for (final entry in reportedProgress.entries)
          {'site_id': entry.key, 'documentation_progress': entry.value},
      ],
    };
    if ((body['sites'] as List).isEmpty) {
      _syncInFlight = false;
      return;
    }

    var succeeded = false;
    try {
      final patch = _patchRequest;
      final response = patch != null
          ? await patch('/api/v1/users/me/site-exploration', body)
          : await _api.patch('/api/v1/users/me/site-exploration', body: body);
      for (final entry in reportedProgress.entries) {
        final local = _progressBySite[entry.key];
        // Keep dirty when progress accrued while this request was in flight.
        if (local != null && local > entry.value + 1e-6) continue;
        _dirtySiteIds.remove(entry.key);
      }
      final profileJson = response['profile'];
      if (profileJson is Map<String, dynamic> && _onProfileUpdated != null) {
        await _onProfileUpdated!(Profile.fromJson(profileJson));
      }
      final sitesJson = response['sites'];
      if (sitesJson is List) {
        final synced = <SiteSummary>[];
        final newlyDocumented = <SiteSummary>[];
        for (final raw in sitesJson) {
          if (raw is! Map<String, dynamic>) continue;
          final site = SiteSummary.fromJson(raw);
          synced.add(site);
          _onSiteUpdated?.call(site);
          final wasDocumented = _documentedSiteIds.contains(site.siteId);
          if (site.documented == true && !wasDocumented) {
            newlyDocumented.add(site);
          }
        }
        // Queue celebrations before ingestSites notifyListeners so the
        // AppShell listener can see them on the first notify.
        if (newlyDocumented.isNotEmpty) {
          _documentationCelebrationQueue.addAll(newlyDocumented);
          playDiscoveryHapticFireAndForget();
        }
        ingestSites(synced);
      }
      await _persistLocal();
      notifyListeners();
      succeeded = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SiteExplorationController.sync: $error');
      }
    } finally {
      _syncInFlight = false;
      // Flush progress accrued during the request (not on failure — avoid loops).
      if (succeeded && _dirtySiteIds.isNotEmpty) {
        unawaited(_syncToBackend(force: force));
      }
    }
  }

  @override
  void dispose() {
    if (_location != null && _locationListener != null) {
      _location!.removeListener(_locationListener!);
    }
    _tickTimer?.cancel();
    super.dispose();
  }
}
