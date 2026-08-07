import 'dart:async';
import 'dart:developer' as developer;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../models/site.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';

/// Auto-discovers nearby field sites inside [discoverRadiusM].
///
/// Walk-in (observed outside → inside) rolls immediately. Opening the app
/// already inside does not roll for free — a dwell timer starts instead.
/// After a chance miss (or while dwelling from baseline), re-rolls every
/// [discoveryRerollInterval] while the user stays inside.
///
/// Rolls are skipped while GPS speed exceeds [discoveryMaxSpeedKmh]
/// (raised by tools like Expedition Drivetrain).
class FieldDiscoveryCoordinator extends ChangeNotifier {
  FieldDiscoveryCoordinator({
    SiteService? siteService,
    Duration? discoveryRerollIntervalOverride,
  }) : _siteService = siteService ?? SiteService(),
       _discoveryRerollIntervalOverride = discoveryRerollIntervalOverride;

  /// YAML client fallback (kept for tests / pre-boost default).
  static double get autoDiscoverRadiusM =>
      GameConfig.instance.siteDiscovery.client.autoDiscoverRadiusM;
  static double get cacheRadiusKm =>
      GameConfig.instance.siteDiscovery.client.cacheRadiusKm;
  static double get cacheRefreshMoveThresholdM =>
      GameConfig.instance.siteDiscovery.client.cacheRefreshMoveThresholdM;
  static Duration get discoverFailRetry => Duration(
    seconds: GameConfig.instance.siteDiscovery.client.discoverFailRetryS,
  );
  static Duration get discoveryRerollIntervalDefault => Duration(
    seconds: GameConfig.instance.siteDiscovery.client.discoveryRerollIntervalS,
  );

  final SiteService _siteService;
  final Duration? _discoveryRerollIntervalOverride;

  /// Effective visibility distance (main param + level/tool). Null → YAML.
  double? _discoverRadiusOverrideM;

  /// Effective max discovery speed (main param + tool). Null → YAML.
  double? _discoveryMaxSpeedKmhOverride;

  Duration get discoveryRerollInterval =>
      _discoveryRerollIntervalOverride ?? discoveryRerollIntervalDefault;

  /// Ground radius used for walk-in / dwell discovery checks.
  double get discoverRadiusM {
    final override = _discoverRadiusOverrideM;
    if (override != null && override > 0) return override;
    if (GameConfig.isLoaded) {
      return GameConfig.instance.siteDiscovery.visibilityDistanceM;
    }
    return autoDiscoverRadiusM;
  }

  /// Max GPS speed (km/h) at which discovery dice may roll.
  double get discoveryMaxSpeedKmh {
    final override = _discoveryMaxSpeedKmhOverride;
    if (override != null && override > 0) return override;
    if (GameConfig.isLoaded) {
      return GameConfig.instance.siteDiscovery.discoveryMaxSpeedKmh;
    }
    return 10.0;
  }

  /// Keep auto-discover aligned with the location-puck pulse / main param.
  void setDiscoverRadiusM(double meters) {
    if (meters <= 0) return;
    if (_discoverRadiusOverrideM == meters) return;
    _discoverRadiusOverrideM = meters;
  }

  /// Keep discovery speed gate aligned with walk XP / tool buffs.
  void setMaxDiscoverySpeedKmh(double kmh) {
    if (kmh <= 0) return;
    if (_discoveryMaxSpeedKmhOverride == kmh) return;
    _discoveryMaxSpeedKmhOverride = kmh;
  }

  LocationService? _locationService;
  VoidCallback? _locationListener;

  List<SiteSummary> _discoverableCache = [];
  LatLng? _lastCachePosition;
  LatLng? _lastHandledLocation;
  double? _cacheRadiusOverrideKm;
  final Set<int> _insideRadiusSiteIds = {};

  /// Sites observed while the user was outside their discover radius.
  /// Required before an inside fix can count as an immediate walk-in roll.
  final Set<int> _seenOutsideSiteIds = {};
  final Set<int> _inFlightSiteIds = {};

  /// Earliest time a discover attempt may run for a site (dwell / network retry).
  final Map<int, DateTime> _nextDiscoverAtBySiteId = {};
  Timer? _dwellTimer;
  Future<void>? _cacheRefreshFuture;

  /// FIFO of discoveries waiting for celebration UI (keeps each site separate).
  final List<FieldDiscoverResponse> _celebrationQueue = [];

  /// Next auto-discovered site waiting for celebration UI (if any).
  FieldDiscoverResponse? get pendingCelebration =>
      _celebrationQueue.isEmpty ? null : _celebrationQueue.first;

  /// Snapshot of the celebration queue (oldest first).
  List<FieldDiscoverResponse> get celebrationQueue =>
      List.unmodifiable(_celebrationQueue);

  /// Read-only snapshot of nearby discoverable (unlinked) field sites.
  List<SiteSummary> get discoverableCache =>
      List<SiteSummary>.unmodifiable(_discoverableCache);

  double get effectiveCacheRadiusKm => _cacheRadiusOverrideKm ?? cacheRadiusKm;

  /// Widen/narrow the nearby-discoverable fetch radius (e.g. Orbit Survey).
  /// Pass null to restore the YAML default.
  void setCacheRadiusOverrideKm(double? km) {
    final next = km;
    if (_cacheRadiusOverrideKm == next) return;
    _cacheRadiusOverrideKm = next;
    // Force a refresh on the next GPS tick / explicit refresh call.
    _lastCachePosition = null;
  }

  /// Nearest discoverable site to [from], or null if cache is empty.
  ({SiteSummary site, double distanceM})? nearestDiscoverable(LatLng from) {
    SiteSummary? best;
    var bestM = double.infinity;
    for (final site in _discoverableCache) {
      final lat = site.latitude;
      final lon = site.longitude;
      if (lat == null || lon == null) continue;
      final d = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        lat,
        lon,
      );
      if (d < bestM) {
        bestM = d;
        best = site;
      }
    }
    if (best == null) return null;
    return (site: best, distanceM: bestM);
  }

  void bind({required LocationService locationService}) {
    if (_locationService != null) {
      return;
    }
    _locationService = locationService;
    _locationListener ??= () => _onLocationChanged(locationService);
    locationService.removeListener(_locationListener!);
    locationService.addListener(_locationListener!);
    final location = locationService.currentLocation;
    if (location != null) {
      _lastHandledLocation = location;
      unawaited(_handleLocationMove(location));
    }
  }

  /// Call after field ensure / resume / map poll so newly visible sites are considered.
  Future<void> refreshDiscoverableCache({bool force = false}) async {
    final location = _locationService?.currentLocation;
    if (location == null) return;
    await _refreshDiscoverableCache(location, force: force);
  }

  /// Merge hidden map sites into the discoverable cache.
  void ingestMapSites(Iterable<SiteSummary> sites) {
    var added = 0;
    for (final site in sites) {
      final status = (site.status ?? 'hidden').trim().toLowerCase();
      if (status != 'hidden') continue;
      if (site.latitude == null || site.longitude == null) continue;
      if (_discoverableCache.any((s) => s.siteId == site.siteId)) continue;
      _discoverableCache.add(site);
      added++;
    }
    if (added == 0) return;
    _log(
      'ingested $added hidden map sites; cache=${_discoverableCache.length}',
    );
  }

  /// Call when the user manually sets a site back to hidden.
  void siteBecameHidden(SiteSummary site) {
    if (site.latitude == null || site.longitude == null) return;
    _insideRadiusSiteIds.remove(site.siteId);
    _seenOutsideSiteIds.remove(site.siteId);
    _nextDiscoverAtBySiteId.remove(site.siteId);
    _discoverableCache.removeWhere((s) => s.siteId == site.siteId);
    _discoverableCache.add(site);
    _armDwellTimer();
    _log('site_id=${site.siteId} hidden again — rediscovery enabled');
  }

  void consumeCelebration() {
    if (_celebrationQueue.isEmpty) return;
    _celebrationQueue.removeAt(0);
    notifyListeners();
  }

  /// Drop all proximity state when the signed-in user changes.
  void clearForUserChange() {
    _dwellTimer?.cancel();
    _dwellTimer = null;
    _discoverableCache = [];
    _lastCachePosition = null;
    _lastHandledLocation = null;
    _cacheRadiusOverrideKm = null;
    _discoverRadiusOverrideM = null;
    _discoveryMaxSpeedKmhOverride = null;
    _insideRadiusSiteIds.clear();
    _seenOutsideSiteIds.clear();
    _inFlightSiteIds.clear();
    _nextDiscoverAtBySiteId.clear();
    _celebrationQueue.clear();
    _cacheRefreshFuture = null;
    _log('cleared for user change');
    notifyListeners();
  }

  void _onLocationChanged(LocationService locationService) {
    final location = locationService.currentLocation;
    if (location == null) return;
    // Ignore heading-only notifies; only act when coordinates change.
    final previous = _lastHandledLocation;
    if (previous != null &&
        previous.latitude == location.latitude &&
        previous.longitude == location.longitude) {
      return;
    }
    _lastHandledLocation = location;
    unawaited(_handleLocationMove(location));
  }

  /// Every GPS move: keep discoverable cache fresh, then check enter/exit.
  Future<void> _handleLocationMove(LatLng location) async {
    await _ensureDiscoverableCache(location);
    await _checkProximity(location);
  }

  Future<void> _ensureDiscoverableCache(LatLng location) async {
    // Empty cache must always be retried — sites often appear after ensure/poll.
    final needsRefresh =
        _discoverableCache.isEmpty ||
        _lastCachePosition == null ||
        _distanceM(_lastCachePosition!, location) >= cacheRefreshMoveThresholdM;
    if (!needsRefresh) return;
    await _refreshDiscoverableCache(
      location,
      force: _discoverableCache.isEmpty,
    );
  }

  Future<void> _refreshDiscoverableCache(
    LatLng location, {
    required bool force,
  }) async {
    if (!force &&
        _lastCachePosition != null &&
        _distanceM(_lastCachePosition!, location) <
            cacheRefreshMoveThresholdM &&
        _discoverableCache.isNotEmpty) {
      return;
    }

    final inFlight = _cacheRefreshFuture;
    if (inFlight != null) {
      await inFlight;
      if (_discoverableCache.isNotEmpty &&
          !force &&
          _lastCachePosition != null &&
          _distanceM(_lastCachePosition!, location) <
              cacheRefreshMoveThresholdM) {
        return;
      }
      // Fall through to refresh again when cache is still empty or forced.
      if (_cacheRefreshFuture != null) {
        await _cacheRefreshFuture;
        if (_discoverableCache.isNotEmpty && !force) return;
      }
    }

    late final Future<void> refresh;
    refresh = () async {
      try {
        final response = await _siteService.fetchNearbyDiscoverableSites(
          lat: location.latitude,
          lon: location.longitude,
          radiusKm: effectiveCacheRadiusKm,
        );
        if (response.items.isNotEmpty) {
          // Prefer server list when present; keep map-ingested ids merged in.
          final byId = {
            for (final site in _discoverableCache) site.siteId: site,
          };
          for (final site in response.items) {
            byId[site.siteId] = site;
          }
          _discoverableCache = byId.values.toList();
        }
        // If the API returns empty (generation lag), keep any map-ingested sites.
        _lastCachePosition = location;
        _log(
          'cache refreshed api=${response.items.length} '
          'cache=${_discoverableCache.length}',
        );
        notifyListeners();
      } catch (error) {
        _log('cache refresh failed error=$error');
      }
    }();

    _cacheRefreshFuture = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_cacheRefreshFuture, refresh)) {
        _cacheRefreshFuture = null;
      }
    }
  }

  Future<void> _checkProximity(LatLng location) async {
    if (_discoverableCache.isEmpty) {
      _log('proximity skip — discoverable cache empty');
      _armDwellTimer();
      return;
    }

    final now = clock.now();
    for (final site in List<SiteSummary>.from(_discoverableCache)) {
      final lat = site.latitude;
      final lon = site.longitude;
      if (lat == null || lon == null) continue;

      final distanceM = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        lat,
        lon,
      );
      final radiusM = discoverRadiusM;
      final inside = distanceM <= radiusM;

      if (!inside) {
        _seenOutsideSiteIds.add(site.siteId);
        if (_insideRadiusSiteIds.remove(site.siteId)) {
          _log('exited site_id=${site.siteId} distance_m=${distanceM.round()}');
        }
        _nextDiscoverAtBySiteId.remove(site.siteId);
        if (kDebugMode && distanceM <= radiusM * 2) {
          _log(
            'near site_id=${site.siteId} distance_m=${distanceM.round()} '
            '(need <= ${radiusM.round()})',
          );
        }
        continue;
      }

      final wasInside = _insideRadiusSiteIds.contains(site.siteId);
      _insideRadiusSiteIds.add(site.siteId);

      // App open / first sight already inside — no free roll; start dwell clock.
      if (!wasInside && !_seenOutsideSiteIds.contains(site.siteId)) {
        _nextDiscoverAtBySiteId[site.siteId] = now.add(discoveryRerollInterval);
        _log(
          'baseline inside site_id=${site.siteId} '
          'distance_m=${distanceM.round()} — dwell '
          '${discoveryRerollInterval.inMilliseconds}ms before first roll',
        );
        continue;
      }

      if (_inFlightSiteIds.contains(site.siteId)) continue;

      final nextAt = _nextDiscoverAtBySiteId[site.siteId];
      // Pending walk-in stays eligible across speed-gate deferrals until a
      // roll actually starts (seenOutside is cleared only then).
      final isWalkIn = _seenOutsideSiteIds.contains(site.siteId);
      if (!isWalkIn) {
        // Still inside: only roll when a dwell/retry is due.
        if (nextAt == null || nextAt.isAfter(now)) continue;
      }

      if (!_isWithinMaxDiscoverySpeed()) {
        // Too fast for a roll — retry shortly (avoid zero-delay dwell loops).
        _nextDiscoverAtBySiteId[site.siteId] = now.add(
          const Duration(seconds: 1),
        );
        _log(
          'speed gate skip site_id=${site.siteId} '
          'distance_m=${distanceM.round()}',
        );
        continue;
      }

      _seenOutsideSiteIds.remove(site.siteId);
      _inFlightSiteIds.add(site.siteId);
      try {
        final updated = await _siteService.discoverSite(
          siteId: site.siteId,
          lat: location.latitude,
          lon: location.longitude,
        );
        _nextDiscoverAtBySiteId.remove(site.siteId);
        _discoverableCache.removeWhere((s) => s.siteId == site.siteId);
        _insideRadiusSiteIds.remove(site.siteId);
        _celebrationQueue.add(updated);
        _log(
          'discovered site_id=${site.siteId} distance_m=${distanceM.round()}',
        );
        notifyListeners();
      } on SiteServiceException catch (error) {
        if (error.isDiscoveryChanceMiss) {
          _nextDiscoverAtBySiteId[site.siteId] = clock.now().add(
            discoveryRerollInterval,
          );
          _log(
            'chance miss site_id=${site.siteId} '
            'distance_m=${distanceM.round()} — dwell '
            '${discoveryRerollInterval.inMilliseconds}ms',
          );
        } else {
          _nextDiscoverAtBySiteId[site.siteId] = clock.now().add(
            discoverFailRetry,
          );
          _log('discover failed site_id=${site.siteId} error=$error');
        }
      } catch (error) {
        _nextDiscoverAtBySiteId[site.siteId] = clock.now().add(
          discoverFailRetry,
        );
        _log('discover failed site_id=${site.siteId} error=$error');
      } finally {
        _inFlightSiteIds.remove(site.siteId);
      }
    }

    _armDwellTimer();
  }

  /// Wake proximity checks while camping (no GPS move) when a dwell is due.
  void _armDwellTimer() {
    _dwellTimer?.cancel();
    _dwellTimer = null;
    if (_nextDiscoverAtBySiteId.isEmpty) return;

    final now = clock.now();
    var soonest = _nextDiscoverAtBySiteId.values.first;
    for (final at in _nextDiscoverAtBySiteId.values) {
      if (at.isBefore(soonest)) soonest = at;
    }
    final delay = soonest.difference(now);
    _dwellTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      final location = _locationService?.currentLocation;
      if (location == null) return;
      unawaited(_checkProximity(location));
    });
  }

  /// True when GPS speed is unknown or at/under [discoveryMaxSpeedKmh].
  bool _isWithinMaxDiscoverySpeed() {
    final speedMps = _locationService?.lastPosition?.speed;
    // Geolocator uses < 0 when speed is unavailable.
    if (speedMps == null || speedMps < 0) return true;
    final maxMps = discoveryMaxSpeedKmh * 1000.0 / 3600.0;
    return speedMps <= maxMps;
  }

  double _distanceM(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  void _log(String message) {
    developer.log('field_discovery action=$message', name: 'field_discovery');
    if (kDebugMode) {
      debugPrint('FieldDiscoveryCoordinator: $message');
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _dwellTimer = null;
    if (_locationListener != null) {
      _locationService?.removeListener(_locationListener!);
    }
    _siteService.dispose();
    super.dispose();
  }
}
