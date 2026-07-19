import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/site.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';

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
  final Set<int> _attemptedSiteIds = {};
  final Set<int> _inFlightSiteIds = {};
  bool _cacheRefreshInFlight = false;
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
      unawaited(refreshDiscoverableCache(force: true));
    }
  }

  /// Call after field ensure / resume so newly generated sites are considered.
  Future<void> refreshDiscoverableCache({bool force = false}) async {
    final location = _locationService?.currentLocation;
    if (location == null) return;

    if (!force &&
        _lastCachePosition != null &&
        _distanceM(_lastCachePosition!, location) < cacheRefreshMoveThresholdM &&
        _discoverableCache.isNotEmpty) {
      return;
    }
    if (_cacheRefreshInFlight) return;
    _cacheRefreshInFlight = true;
    try {
      final response = await _siteService.fetchNearbyDiscoverableSites(
        lat: location.latitude,
        lon: location.longitude,
        radiusKm: cacheRadiusKm,
      );
      _discoverableCache = List<SiteSummary>.from(response.items);
      _lastCachePosition = location;
      _log('cache refreshed count=${_discoverableCache.length}');
      notifyListeners();
      await _checkProximity(location);
    } catch (error) {
      _log('cache refresh failed error=$error');
    } finally {
      _cacheRefreshInFlight = false;
    }
  }

  void consumeCelebration() {
    _celebrationConsumed = true;
    _pendingCelebration = null;
    notifyListeners();
  }

  void _onLocationChanged(LocationService locationService) {
    final location = locationService.currentLocation;
    if (location == null) return;
    unawaited(_maybeRefreshCacheOnMove(location));
    unawaited(_checkProximity(location));
  }

  Future<void> _maybeRefreshCacheOnMove(LatLng location) async {
    if (_lastCachePosition == null) {
      await refreshDiscoverableCache(force: true);
      return;
    }
    if (_distanceM(_lastCachePosition!, location) >= cacheRefreshMoveThresholdM) {
      await refreshDiscoverableCache(force: true);
    }
  }

  Future<void> _checkProximity(LatLng location) async {
    if (_discoverableCache.isEmpty) return;

    for (final site in List<SiteSummary>.from(_discoverableCache)) {
      final lat = site.latitude;
      final lon = site.longitude;
      if (lat == null || lon == null) continue;
      if (_attemptedSiteIds.contains(site.siteId)) continue;
      if (_inFlightSiteIds.contains(site.siteId)) continue;

      final distanceM = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        lat,
        lon,
      );
      if (distanceM > autoDiscoverRadiusM) continue;

      _inFlightSiteIds.add(site.siteId);
      try {
        final updated = await _siteService.discoverSite(
          siteId: site.siteId,
          lat: location.latitude,
          lon: location.longitude,
        );
        _attemptedSiteIds.add(site.siteId);
        _discoverableCache.removeWhere((s) => s.siteId == site.siteId);
        _pendingCelebration = updated;
        _celebrationConsumed = false;
        HapticFeedback.heavyImpact();
        _log('discovered site_id=${site.siteId} distance_m=${distanceM.round()}');
        notifyListeners();
      } catch (error) {
        // Keep attempting later only for transient failures; permanent distance
        // errors should not spam — still mark attempted for this session.
        _attemptedSiteIds.add(site.siteId);
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
