import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/game_config.dart';
import '../models/profile.dart';
import '../models/site.dart';
import '../services/api_client.dart';
import '../services/gps_odometer.dart';
import '../services/location_service.dart';
import '../utils/discovery_haptic.dart';
import '../widgets/cards/site_dimension_display.dart';

/// Accrues path meters walked inside [documentationDistanceM] of discovered sites.
class SiteExplorationController extends ChangeNotifier {
  SiteExplorationController({
    ApiClient? apiClient,
    GpsOdometer? odometer,
  })  : _api = apiClient ?? ApiClient.instance,
        _odometer = odometer ??
            GpsOdometer(
              maxSpeedMps: _maxDiscoverySpeedMps(),
            );

  static const _prefsKey = 'site_exploration_v1';
  static const _syncInterval = Duration(seconds: 30);

  final ApiClient _api;
  final GpsOdometer _odometer;

  LocationService? _location;
  VoidCallback? _locationListener;
  List<SiteSummary> Function()? _discoveredSitesProvider;
  int Function()? _skillLevelProvider;
  Future<void> Function(Profile profile)? _onProfileUpdated;
  void Function(SiteSummary site)? _onSiteUpdated;

  /// Local explored meters by site id (monotonic).
  final Map<int, double> _exploredBySite = {};
  final Set<int> _documentedSiteIds = {};
  final Set<int> _dirtySiteIds = {};
  DateTime? _lastSyncAttemptAt;
  bool _syncInFlight = false;
  bool _appForeground = true;
  bool _loaded = false;

  SiteSummary? _pendingDocumentationCelebration;
  bool _documentationCelebrationConsumed = false;

  Map<int, double> get exploredBySite => Map.unmodifiable(_exploredBySite);

  bool isDocumented(int siteId) => _documentedSiteIds.contains(siteId);

  SiteSummary? get pendingDocumentationCelebration =>
      _documentationCelebrationConsumed
          ? null
          : _pendingDocumentationCelebration;

  void consumeDocumentationCelebration() {
    _documentationCelebrationConsumed = true;
    _pendingDocumentationCelebration = null;
    notifyListeners();
  }

  /// Best-known explored meters for [siteId] (local buffer wins when ahead).
  /// Documented sites stay frozen at the known value (no local overshoot).
  double exploredMetersFor(int siteId, {double fallback = 0.0}) {
    final local = _exploredBySite[siteId];
    if (local == null) return fallback;
    if (_documentedSiteIds.contains(siteId)) {
      return local;
    }
    return local > fallback ? local : fallback;
  }

  static double _maxDiscoverySpeedMps() {
    try {
      final kmh = GameConfig.instance.siteDiscovery.discoveryMaxSpeedKmh;
      return kmh * 1000.0 / 3600.0;
    } catch (_) {
      return 5.56;
    }
  }

  double? _documentationDistanceMOverride;

  double get documentationDistanceM {
    if (_documentationDistanceMOverride != null) return _documentationDistanceMOverride!;
    try {
      if (!GameConfig.isLoaded) return 50.0;
      return GameConfig.instance.siteStewardship.mainParams.documentationDistanceM;
    } catch (_) {
      return 50.0;
    }
  }

  void updateMaxDiscoverySpeedKmh(double kmh) {
    final mps = kmh * 1000.0 / 3600.0;
    if ((_odometer.maxSpeedMps - mps).abs() < 0.01) return;
    _odometer.maxSpeedMps = mps;
  }

  void updateSiteVisibilityM(double meters) {
    if (_documentationDistanceMOverride != null &&
        (_documentationDistanceMOverride! - meters).abs() < 0.01) {
      return;
    }
    _documentationDistanceMOverride = meters;
  }

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
    // One-shot sync so backend can award documentation on already-complete sites.
    for (final id in _exploredBySite.keys) {
      if (!_documentedSiteIds.contains(id)) {
        _dirtySiteIds.add(id);
      }
    }
    _location = location;
    _locationListener = () {
      final allow =
          location.isAppForeground || location.isBackgroundExploring;
      if (!allow) return;
      unawaited(_ingestPosition(location.lastPosition));
    };
    location.addListener(_locationListener!);
    if (_dirtySiteIds.isNotEmpty) {
      unawaited(_syncToBackend(force: true));
    }
  }

  /// Seed / raise local counters from server site summaries.
  ///
  /// Server is authoritative when the viewer has no discoverer progress
  /// (`exploredDistanceM == null`) or when local is not dirty and behind.
  void ingestSites(Iterable<SiteSummary> sites) {
    var changed = false;
    for (final site in sites) {
      final server = site.exploredDistanceM;
      if (server == null) {
        // No discoverer link / progress for viewer — drop stale local buffer.
        if (_exploredBySite.remove(site.siteId) != null) changed = true;
        if (_documentedSiteIds.remove(site.siteId)) changed = true;
        _dirtySiteIds.remove(site.siteId);
        continue;
      }

      if (site.documented == true) {
        if (_documentedSiteIds.add(site.siteId)) changed = true;
        if ((_exploredBySite[site.siteId] ?? -1) != server) {
          _exploredBySite[site.siteId] = server;
          changed = true;
        }
        continue;
      }

      if (_documentedSiteIds.remove(site.siteId)) changed = true;
      final local = _exploredBySite[site.siteId];
      final dirty = _dirtySiteIds.contains(site.siteId);
      if (local == null || server > local || (!dirty && server < local)) {
        if (local != server) {
          _exploredBySite[site.siteId] = server;
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
    if (_exploredBySite.isEmpty &&
        _documentedSiteIds.isEmpty &&
        _dirtySiteIds.isEmpty) {
      return;
    }
    _exploredBySite.clear();
    _documentedSiteIds.clear();
    _dirtySiteIds.clear();
    await _persistLocal();
    notifyListeners();
  }

  void onAppResumed() {
    _appForeground = true;
    final exploring = _location?.isBackgroundExploring ?? false;
    if (!exploring) {
      _odometer.reset();
    }
  }

  Future<void> onAppBackgrounded() async {
    _appForeground = false;
    final exploring = _location?.isBackgroundExploring ?? false;
    if (!exploring) {
      _odometer.reset();
    }
    await _syncToBackend(force: true);
  }

  Future<void> _loadLocal() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        final meters = (entry.value as num?)?.toDouble();
        if (id == null || meters == null) continue;
        _exploredBySite[id] = meters;
      }
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
        for (final e in _exploredBySite.entries) '${e.key}': e.value,
      };
      await prefs.setString(_prefsKey, jsonEncode(encoded));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SiteExplorationController.persist: $error');
      }
    }
  }

  Future<void> _ingestPosition(Position? position) async {
    if (position == null) return;
    final allow = _appForeground ||
        (_location?.isBackgroundExploring ?? false);
    if (!allow) return;
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

    final sites = _discoveredSitesProvider?.call() ?? const <SiteSummary>[];
    if (sites.isEmpty) return;

    final radius = documentationDistanceM;
    final skillLevel = _skillLevelProvider?.call() ?? 1;
    var credited = false;
    var documentationReady = false;
    for (final site in sites) {
      final lat = site.latitude;
      final lon = site.longitude;
      if (lat == null || lon == null) continue;
      if (site.discoveredAt == null &&
          (site.status == null || site.status == 'hidden')) {
        continue;
      }
      if (site.needsIdentification) {
        continue;
      }
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lon,
      );
      if (distance > radius) continue;
      if (site.documented == true ||
          _documentedSiteIds.contains(site.siteId)) {
        continue;
      }
      final previous =
          _exploredBySite[site.siteId] ?? site.exploredDistanceM ?? 0.0;
      final next = previous + result.acceptedMeters;
      _exploredBySite[site.siteId] = next;
      _dirtySiteIds.add(site.siteId);
      credited = true;
      if (siteIsFullyDocumented(
        siteId: site.siteId,
        oddDinoCount: site.oddDinoCount,
        oddFossilCount: site.oddFossilCount,
        oddCompleteness: site.oddCompleteness,
        oddQuality: site.oddQuality,
        oddDepth: site.oddDepth,
        skillLevel: skillLevel,
        exploredDistanceM: next,
      )) {
        documentationReady = true;
      }
    }
    if (!credited) return;
    await _persistLocal();
    notifyListeners();
    // Force sync as soon as local meters would complete documentation so
    // celebration / XP / status don't wait on the 30s interval.
    unawaited(_syncToBackend(force: documentationReady));
  }

  Future<void> _syncToBackend({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastSyncAttemptAt != null &&
        now.difference(_lastSyncAttemptAt!) < _syncInterval) {
      return;
    }
    if (_dirtySiteIds.isEmpty || _syncInFlight) return;
    _lastSyncAttemptAt = now;
    _syncInFlight = true;

    final toSync = _dirtySiteIds.toList();
    final reportedMeters = <int, double>{
      for (final siteId in toSync)
        if (_exploredBySite.containsKey(siteId))
          siteId: _exploredBySite[siteId]!,
    };
    final body = {
      'sites': [
        for (final entry in reportedMeters.entries)
          {
            'site_id': entry.key,
            'explored_distance_m': entry.value,
          },
      ],
    };
    if ((body['sites'] as List).isEmpty) {
      _syncInFlight = false;
      return;
    }

    var succeeded = false;
    try {
      final response = await _api.patch(
        '/api/v1/users/me/site-exploration',
        body: body,
      );
      for (final entry in reportedMeters.entries) {
        final local = _exploredBySite[entry.key];
        // Keep dirty when meters accrued while this request was in flight.
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
        SiteSummary? newlyDocumented;
        for (final raw in sitesJson) {
          if (raw is! Map<String, dynamic>) continue;
          final site = SiteSummary.fromJson(raw);
          synced.add(site);
          _onSiteUpdated?.call(site);
          final wasDocumented = _documentedSiteIds.contains(site.siteId);
          if (site.documented == true && !wasDocumented) {
            newlyDocumented = site;
          }
        }
        // Set pending celebration before ingestSites notifyListeners so the
        // AppShell listener can see it on the first notify.
        if (newlyDocumented != null) {
          _pendingDocumentationCelebration = newlyDocumented;
          _documentationCelebrationConsumed = false;
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
      // Flush meters accrued during the request (not on failure — avoid loops).
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
    super.dispose();
  }
}
