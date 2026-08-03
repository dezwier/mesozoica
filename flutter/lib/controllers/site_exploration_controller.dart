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

/// Accrues path meters walked inside [siteVisibilityM] of discovered sites.
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
  Future<void> Function(Profile profile)? _onProfileUpdated;
  void Function(SiteSummary site)? _onSiteUpdated;

  /// Local explored meters by site id (monotonic).
  final Map<int, double> _exploredBySite = {};
  final Set<int> _dirtySiteIds = {};
  DateTime? _lastSyncAttemptAt;
  bool _appForeground = true;
  bool _loaded = false;

  Map<int, double> get exploredBySite => Map.unmodifiable(_exploredBySite);

  /// Best-known explored meters for [siteId] (local buffer wins when ahead).
  double exploredMetersFor(int siteId, {double fallback = 0.0}) {
    final local = _exploredBySite[siteId];
    if (local == null) return fallback;
    return local > fallback ? local : fallback;
  }

  static double _maxDiscoverySpeedMps() {
    try {
      final kmh = GameConfig.instance.siteDiscovery.maxDiscoverySpeedKmh;
      return kmh * 1000.0 / 3600.0;
    } catch (_) {
      return 5.56;
    }
  }

  double get siteVisibilityM {
    try {
      if (!GameConfig.isLoaded) return 50.0;
      return GameConfig.instance.siteStewardship.mainParams.siteVisibilityM;
    } catch (_) {
      return 50.0;
    }
  }

  void updateMaxDiscoverySpeedKmh(double kmh) {
    final mps = kmh * 1000.0 / 3600.0;
    if ((_odometer.maxSpeedMps - mps).abs() < 0.01) return;
    _odometer.maxSpeedMps = mps;
  }

  Future<void> bind(
    LocationService location, {
    required List<SiteSummary> Function() discoveredSitesProvider,
    Future<void> Function(Profile profile)? onProfileUpdated,
    void Function(SiteSummary site)? onSiteUpdated,
  }) async {
    _discoveredSitesProvider = discoveredSitesProvider;
    _onProfileUpdated = onProfileUpdated;
    _onSiteUpdated = onSiteUpdated;
    if (_location != null) return;
    await _loadLocal();
    _location = location;
    _locationListener = () {
      if (!_appForeground) return;
      if (!location.isAppForeground) return;
      unawaited(_ingestPosition(location.lastPosition));
    };
    location.addListener(_locationListener!);
  }

  /// Seed / raise local counters from server site summaries.
  void ingestSites(Iterable<SiteSummary> sites) {
    var changed = false;
    for (final site in sites) {
      final server = site.exploredDistanceM;
      if (server == null) continue;
      final local = _exploredBySite[site.siteId] ?? 0.0;
      if (server > local) {
        _exploredBySite[site.siteId] = server;
        changed = true;
      }
    }
    if (changed) {
      unawaited(_persistLocal());
      notifyListeners();
    }
  }

  void onAppResumed() {
    _appForeground = true;
    _odometer.reset();
  }

  Future<void> onAppBackgrounded() async {
    _appForeground = false;
    _odometer.reset();
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
    if (!_appForeground || position == null) return;
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

    final radius = siteVisibilityM;
    var credited = false;
    for (final site in sites) {
      final lat = site.latitude;
      final lon = site.longitude;
      if (lat == null || lon == null) continue;
      if (site.discoveredAt == null &&
          (site.status == null || site.status == 'hidden')) {
        continue;
      }
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lon,
      );
      if (distance > radius) continue;
      final previous =
          _exploredBySite[site.siteId] ?? site.exploredDistanceM ?? 0.0;
      _exploredBySite[site.siteId] = previous + result.acceptedMeters;
      _dirtySiteIds.add(site.siteId);
      credited = true;
    }
    if (!credited) return;
    await _persistLocal();
    notifyListeners();
    unawaited(_syncToBackend());
  }

  Future<void> _syncToBackend({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastSyncAttemptAt != null &&
        now.difference(_lastSyncAttemptAt!) < _syncInterval) {
      return;
    }
    if (_dirtySiteIds.isEmpty) return;
    _lastSyncAttemptAt = now;

    final toSync = _dirtySiteIds.toList();
    final body = {
      'sites': [
        for (final siteId in toSync)
          if (_exploredBySite.containsKey(siteId))
            {
              'site_id': siteId,
              'explored_distance_m': _exploredBySite[siteId],
            },
      ],
    };
    if ((body['sites'] as List).isEmpty) return;

    try {
      final response = await _api.patch(
        '/api/v1/users/me/site-exploration',
        body: body,
      );
      for (final siteId in toSync) {
        _dirtySiteIds.remove(siteId);
      }
      final profileJson = response['profile'];
      if (profileJson is Map<String, dynamic> && _onProfileUpdated != null) {
        await _onProfileUpdated!(Profile.fromJson(profileJson));
      }
      final sitesJson = response['sites'];
      if (sitesJson is List) {
        for (final raw in sitesJson) {
          if (raw is! Map<String, dynamic>) continue;
          final site = SiteSummary.fromJson(raw);
          final server = site.exploredDistanceM ?? 0.0;
          final local = _exploredBySite[site.siteId] ?? 0.0;
          if (server > local) {
            _exploredBySite[site.siteId] = server;
          }
          _onSiteUpdated?.call(site);
        }
      }
      await _persistLocal();
      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SiteExplorationController.sync: $error');
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
