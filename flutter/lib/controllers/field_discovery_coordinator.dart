import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../models/site.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';
import '../utils/discovery_haptic.dart';

/// Auto-discovers nearby field sites on enter into [autoDiscoverRadiusM].
///
/// Discovery requires a real walk-in: the user must be observed outside the
/// radius, then cross into it. Opening the app (or refreshing the cache) while
/// already standing inside does not discover. A chance miss does not retry
/// until the user leaves and re-enters the radius.
class FieldDiscoveryCoordinator extends ChangeNotifier {
  FieldDiscoveryCoordinator({SiteService? siteService})
      : _siteService = siteService ?? SiteService();

  static double get autoDiscoverRadiusM =>
      GameConfig.instance.siteDiscovery.client.autoDiscoverRadiusM;
  static double get cacheRadiusKm =>
      GameConfig.instance.siteDiscovery.client.cacheRadiusKm;
  static double get cacheRefreshMoveThresholdM =>
      GameConfig.instance.siteDiscovery.client.cacheRefreshMoveThresholdM;
  static Duration get discoverFailRetry => Duration(
        seconds: GameConfig.instance.siteDiscovery.client.discoverFailRetryS,
      );

  final SiteService _siteService;
  LocationService? _locationService;
  VoidCallback? _locationListener;

  List<SiteSummary> _discoverableCache = [];
  LatLng? _lastCachePosition;
  LatLng? _lastHandledLocation;
  double? _cacheRadiusOverrideKm;
  final Set<int> _insideRadiusSiteIds = {};
  /// Sites observed while the user was outside their discover radius.
  /// Required before an inside fix can count as a walk-in enter.
  final Set<int> _seenOutsideSiteIds = {};
  final Set<int> _attemptedThisVisitSiteIds = {};
  final Set<int> _inFlightSiteIds = {};
  final Map<int, DateTime> _retryAfterBySiteId = {};
  Future<void>? _cacheRefreshFuture;
  FieldDiscoverResponse? _pendingCelebration;
  bool _celebrationConsumed = false;

  /// Latest auto-discovered site waiting for celebration UI (if any).
  FieldDiscoverResponse? get pendingCelebration =>
      _celebrationConsumed ? null : _pendingCelebration;

  /// Read-only snapshot of nearby discoverable (unlinked) field sites.
  List<SiteSummary> get discoverableCache =>
      List<SiteSummary>.unmodifiable(_discoverableCache);

  double get effectiveCacheRadiusKm =>
      _cacheRadiusOverrideKm ?? cacheRadiusKm;

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
  ///
  /// If a site was auto-discovered then set back to hidden, clear visit state
  /// so the next enter (or current enter) can discover it again.
  void ingestMapSites(Iterable<SiteSummary> sites) {
    var added = 0;
    for (final site in sites) {
      final status = (site.status ?? 'hidden').trim().toLowerCase();
      if (status != 'hidden') continue;
      if (site.latitude == null || site.longitude == null) continue;

      _attemptedThisVisitSiteIds.remove(site.siteId);
      _retryAfterBySiteId.remove(site.siteId);

      if (_discoverableCache.any((s) => s.siteId == site.siteId)) continue;
      _discoverableCache.add(site);
      added++;
    }
    if (added == 0) return;
    _log('ingested $added hidden map sites; cache=${_discoverableCache.length}');
  }

  /// Call when the user manually sets a site back to hidden.
  void siteBecameHidden(SiteSummary site) {
    if (site.latitude == null || site.longitude == null) return;
    _attemptedThisVisitSiteIds.remove(site.siteId);
    _insideRadiusSiteIds.remove(site.siteId);
    _seenOutsideSiteIds.remove(site.siteId);
    _retryAfterBySiteId.remove(site.siteId);
    _discoverableCache.removeWhere((s) => s.siteId == site.siteId);
    _discoverableCache.add(site);
    _log('site_id=${site.siteId} hidden again — rediscovery enabled');
  }

  void consumeCelebration() {
    _celebrationConsumed = true;
    _pendingCelebration = null;
    notifyListeners();
  }

  /// Drop all proximity state when the signed-in user changes.
  void clearForUserChange() {
    _discoverableCache = [];
    _lastCachePosition = null;
    _lastHandledLocation = null;
    _cacheRadiusOverrideKm = null;
    _insideRadiusSiteIds.clear();
    _seenOutsideSiteIds.clear();
    _attemptedThisVisitSiteIds.clear();
    _inFlightSiteIds.clear();
    _retryAfterBySiteId.clear();
    _pendingCelebration = null;
    _celebrationConsumed = false;
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
    final needsRefresh = _discoverableCache.isEmpty ||
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
        _distanceM(_lastCachePosition!, location) < cacheRefreshMoveThresholdM &&
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
        _log('cache refreshed api=${response.items.length} '
            'cache=${_discoverableCache.length}');
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
      return;
    }

    final now = DateTime.now();
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
      final inside = distanceM <= autoDiscoverRadiusM;

      if (!inside) {
        _seenOutsideSiteIds.add(site.siteId);
        if (_insideRadiusSiteIds.remove(site.siteId)) {
          _attemptedThisVisitSiteIds.remove(site.siteId);
          _log(
            'exited site_id=${site.siteId} distance_m=${distanceM.round()}',
          );
        }
        if (kDebugMode && distanceM <= autoDiscoverRadiusM * 2) {
          _log(
            'near site_id=${site.siteId} distance_m=${distanceM.round()} '
            '(need <= ${autoDiscoverRadiusM.round()})',
          );
        }
        continue;
      }

      final wasInside = _insideRadiusSiteIds.contains(site.siteId);
      _insideRadiusSiteIds.add(site.siteId);
      if (wasInside) {
        // Still inside this visit — do not re-attempt.
        continue;
      }

      // Already here on first sight (app open / cache load) — not a walk-in.
      if (!_seenOutsideSiteIds.contains(site.siteId)) {
        _log(
          'baseline inside site_id=${site.siteId} '
          'distance_m=${distanceM.round()} — walk out and in to discover',
        );
        continue;
      }

      // Walk-in enter: previously outside, now inside.
      if (_attemptedThisVisitSiteIds.contains(site.siteId)) continue;
      if (_inFlightSiteIds.contains(site.siteId)) continue;
      final retryAfter = _retryAfterBySiteId[site.siteId];
      if (retryAfter != null && retryAfter.isAfter(now)) continue;

      _seenOutsideSiteIds.remove(site.siteId);
      _inFlightSiteIds.add(site.siteId);
      try {
        final updated = await _siteService.discoverSite(
          siteId: site.siteId,
          lat: location.latitude,
          lon: location.longitude,
        );
        _attemptedThisVisitSiteIds.add(site.siteId);
        _retryAfterBySiteId.remove(site.siteId);
        _discoverableCache.removeWhere((s) => s.siteId == site.siteId);
        _insideRadiusSiteIds.remove(site.siteId);
        _pendingCelebration = updated;
        _celebrationConsumed = false;
        playDiscoveryHapticFireAndForget();
        _log('discovered site_id=${site.siteId} distance_m=${distanceM.round()}');
        notifyListeners();
      } on SiteServiceException catch (error) {
        if (error.isDiscoveryChanceMiss) {
          _attemptedThisVisitSiteIds.add(site.siteId);
          _retryAfterBySiteId.remove(site.siteId);
          _log(
            'chance miss site_id=${site.siteId} '
            'distance_m=${distanceM.round()} — wait for exit',
          );
        } else {
          _retryAfterBySiteId[site.siteId] = now.add(discoverFailRetry);
          // Allow another enter-attempt after retry window: treat as not yet
          // rolled this visit, and clear inside so the next GPS tick can re-enter.
          _insideRadiusSiteIds.remove(site.siteId);
          _seenOutsideSiteIds.add(site.siteId);
          _log('discover failed site_id=${site.siteId} error=$error');
        }
      } catch (error) {
        _retryAfterBySiteId[site.siteId] = now.add(discoverFailRetry);
        _insideRadiusSiteIds.remove(site.siteId);
        _seenOutsideSiteIds.add(site.siteId);
        _log('discover failed site_id=${site.siteId} error=$error');
      } finally {
        _inFlightSiteIds.remove(site.siteId);
      }
    }
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
    developer.log(
      'field_discovery action=$message',
      name: 'field_discovery',
    );
    if (kDebugMode) {
      debugPrint('FieldDiscoveryCoordinator: $message');
    }
  }

  @override
  void dispose() {
    if (_locationListener != null) {
      _locationService?.removeListener(_locationListener!);
    }
    _siteService.dispose();
    super.dispose();
  }
}
