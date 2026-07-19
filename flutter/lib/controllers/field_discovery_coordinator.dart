import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/site.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';
import '../utils/discovery_haptic.dart';

/// Auto-discovers nearby field sites within [autoDiscoverRadiusM].
class FieldDiscoveryCoordinator extends ChangeNotifier {
  FieldDiscoveryCoordinator({SiteService? siteService})
      : _siteService = siteService ?? SiteService();

  static const autoDiscoverRadiusM = 50.0;
  static const cacheRadiusKm = 1.0;
  static const cacheRefreshMoveThresholdM = 500.0;

  final SiteService _siteService;
  LocationService? _locationService;
  VoidCallback? _locationListener;

  List<SiteSummary> _discoverableCache = [];
  LatLng? _lastCachePosition;
  LatLng? _lastHandledLocation;
  final Set<int> _attemptedSiteIds = {};
  final Set<int> _inFlightSiteIds = {};
  final Map<int, DateTime> _retryAfterBySiteId = {};
  Future<void>? _cacheRefreshFuture;
  SiteSummary? _pendingCelebration;
  bool _celebrationConsumed = false;

  /// Latest auto-discovered site waiting for celebration UI (if any).
  SiteSummary? get pendingCelebration =>
      _celebrationConsumed ? null : _pendingCelebration;

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
  /// If a site was auto-discovered then set back to hidden, clear the session
  /// blacklist so the next GPS move can discover it again.
  void ingestMapSites(Iterable<SiteSummary> sites) {
    var added = 0;
    for (final site in sites) {
      final status = (site.status ?? 'hidden').trim().toLowerCase();
      if (status != 'hidden') continue;
      if (site.latitude == null || site.longitude == null) continue;

      _attemptedSiteIds.remove(site.siteId);
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
    _attemptedSiteIds.remove(site.siteId);
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

  /// Every GPS move: keep discoverable cache fresh, then check 50 m proximity.
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
          radiusKm: cacheRadiusKm,
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
      if (_attemptedSiteIds.contains(site.siteId)) continue;
      if (_inFlightSiteIds.contains(site.siteId)) continue;
      final retryAfter = _retryAfterBySiteId[site.siteId];
      if (retryAfter != null && retryAfter.isAfter(now)) continue;

      final distanceM = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        lat,
        lon,
      );
      if (distanceM > autoDiscoverRadiusM) {
        if (kDebugMode && distanceM <= autoDiscoverRadiusM * 2) {
          _log(
            'near site_id=${site.siteId} distance_m=${distanceM.round()} '
            '(need <= ${autoDiscoverRadiusM.round()})',
          );
        }
        continue;
      }

      _inFlightSiteIds.add(site.siteId);
      try {
        final updated = await _siteService.discoverSite(
          siteId: site.siteId,
          lat: location.latitude,
          lon: location.longitude,
        );
        _attemptedSiteIds.add(site.siteId);
        _retryAfterBySiteId.remove(site.siteId);
        _discoverableCache.removeWhere((s) => s.siteId == site.siteId);
        _pendingCelebration = updated;
        _celebrationConsumed = false;
        playDiscoveryHapticFireAndForget();
        _log('discovered site_id=${site.siteId} distance_m=${distanceM.round()}');
        notifyListeners();
      } catch (error) {
        _retryAfterBySiteId[site.siteId] =
            now.add(const Duration(seconds: 20));
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
