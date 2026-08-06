import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../config/map_config.dart';
import '../../../controllers/catalog_mode_controller.dart';
import '../../../models/site.dart';
import '../../../utils/map_visible_bounds.dart';
import '../data/site_repository.dart';
import 'map_catalog_cache.dart';

enum ShowAllLoadResult { success, tooMany, failed, cancelled }

/// Owns on-demand field viewport loading and request coalescing.
class MapViewportLoader {
  MapViewportLoader({
    required SiteService service,
    required MapCatalogSnapshot Function() snapshot,
    required bool Function() isFieldMode,
    required bool Function() isEnabled,
    required List<SiteSummary> Function(List<SiteSummary>) withCoordinates,
    required LatLngBounds? Function(LatLngBounds?, List<SiteSummary>)
    expandBounds,
    required VoidCallback notifyChanged,
  }) : _service = service,
       _snapshot = snapshot,
       _isFieldMode = isFieldMode,
       _isEnabled = isEnabled,
       _withCoordinates = withCoordinates,
       _expandBounds = expandBounds,
       _notifyChanged = notifyChanged;

  final SiteService _service;
  final MapCatalogSnapshot Function() _snapshot;
  final bool Function() _isFieldMode;
  final bool Function() _isEnabled;
  final List<SiteSummary> Function(List<SiteSummary>) _withCoordinates;
  final LatLngBounds? Function(LatLngBounds?, List<SiteSummary>) _expandBounds;
  final VoidCallback _notifyChanged;

  LatLngBounds? bounds;
  LatLngBounds? pendingBounds;
  DateTime? loadStartedAt;
  bool authoritative = false;

  void reset() {
    bounds = null;
    pendingBounds = null;
    loadStartedAt = null;
    authoritative = false;
  }

  Future<ShowAllLoadResult> load(
    LatLngBounds requestedBounds, {
    bool force = false,
  }) async {
    if (!_isFieldMode() || !_isEnabled()) {
      return ShowAllLoadResult.cancelled;
    }
    final safe = clampBoundsForSitesApi(requestedBounds);
    final snap = _snapshot();
    if (safe == null) {
      snap.error =
          'Map view is too large to load sites. Zoom in and try again.';
      return ShowAllLoadResult.failed;
    }
    requestedBounds = safe;
    if (!force &&
        snap.loadingComplete &&
        !snap.loading &&
        bounds != null &&
        _sameBounds(bounds!, requestedBounds)) {
      return ShowAllLoadResult.success;
    }

    if (snap.loading) {
      final started = loadStartedAt;
      final stale =
          started != null &&
          DateTime.now().difference(started) > const Duration(seconds: 25);
      if (!stale) {
        pendingBounds = requestedBounds;
        return ShowAllLoadResult.cancelled;
      }
      ++snap.loadSeq;
      snap.loading = false;
      pendingBounds = null;
    }

    pendingBounds = null;
    bounds = requestedBounds;
    loadStartedAt = DateTime.now();
    final seq = ++snap.loadSeq;
    snap.loading = true;
    snap.loadingComplete = false;
    snap.error = null;
    _notifyChanged();
    return _loadPages(seq, requestedBounds);
  }

  bool _sameBounds(LatLngBounds a, LatLngBounds b) =>
      a.south == b.south &&
      a.north == b.north &&
      a.west == b.west &&
      a.east == b.east;

  Future<ShowAllLoadResult> _loadPages(int seq, LatLngBounds bounds) async {
    final snap = _snapshot();
    var result = ShowAllLoadResult.failed;
    try {
      if (seq != snap.loadSeq || !_isEnabled()) {
        return ShowAllLoadResult.cancelled;
      }

      final allGeo = <SiteSummary>[];
      var offset = 0;
      var total = 0;
      var hasMore = true;
      while (hasMore) {
        if (seq != snap.loadSeq || !_isEnabled()) {
          return ShowAllLoadResult.cancelled;
        }
        final response = await _service.fetchSites(
          limit: 500,
          offset: offset,
          sort: 'name',
          dataSource: CatalogDataSource.field,
          showAll: true,
          minLat: bounds.south,
          maxLat: bounds.north,
          minLon: bounds.west,
          maxLon: bounds.east,
        );
        if (seq != snap.loadSeq || !_isEnabled()) {
          return ShowAllLoadResult.cancelled;
        }

        total = response.total;
        if (total > MapConfig.showAllMaxSites) {
          authoritative = false;
          snap.geoSites = [];
          snap.siteBounds = null;
          snap.loadedCatalog = 0;
          snap.totalCatalog = total;
          snap.maxFieldSiteId = 0;
          snap.error =
              'Too many sites in this view ($total). '
              'Zoom in and try again (max ${MapConfig.showAllMaxSites}).';
          snap.loadingComplete = false;
          return ShowAllLoadResult.tooMany;
        }

        final geo = _withCoordinates(response.items);
        allGeo.addAll(geo);
        offset += response.items.length;
        hasMore =
            response.hasMore &&
            response.items.isNotEmpty &&
            allGeo.length < total;
      }

      if (seq != snap.loadSeq || !_isEnabled()) {
        return ShowAllLoadResult.cancelled;
      }
      snap.geoSites = List<SiteSummary>.from(allGeo);
      snap.siteBounds = _expandBounds(null, allGeo);
      snap.maxFieldSiteId = allGeo.fold(
        0,
        (max, site) => site.siteId > max ? site.siteId : max,
      );
      snap.loadedCatalog = allGeo.length;
      snap.totalCatalog = total;
      snap.error = null;
      snap.loadingComplete = true;
      snap.loadedAt = DateTime.now();
      authoritative = true;
      result = ShowAllLoadResult.success;
      if (kDebugMode) {
        debugPrint(
          'MapController: show-all viewport — ${allGeo.length} markers '
          '(${snap.loadedCatalog}/${snap.totalCatalog} in bbox, '
          'show_all authoritative)',
        );
      }
      if (_isFieldMode() && _isEnabled()) _notifyChanged();
      return result;
    } on SiteServiceException catch (error) {
      if (seq != snap.loadSeq) return ShowAllLoadResult.cancelled;
      authoritative = false;
      snap.error = error.message;
      snap.loadingComplete = false;
      return ShowAllLoadResult.failed;
    } on TimeoutException catch (error) {
      if (seq != snap.loadSeq) return ShowAllLoadResult.cancelled;
      authoritative = false;
      snap.loadingComplete = false;
      final seconds = error.duration?.inSeconds;
      snap.error = seconds != null
          ? 'Timed out loading sites in view after ${seconds}s — try again.'
          : 'Timed out loading sites in view — try again.';
      if (kDebugMode) {
        debugPrint('MapController.load show-all viewport timed out: $error');
      }
      return ShowAllLoadResult.failed;
    } catch (error) {
      if (seq != snap.loadSeq) return ShowAllLoadResult.cancelled;
      authoritative = false;
      snap.loadingComplete = false;
      snap.error = 'Could not load sites in view: $error';
      if (kDebugMode) {
        debugPrint('MapController.load show-all viewport failed: $error');
      }
      return ShowAllLoadResult.failed;
    } finally {
      if (seq == snap.loadSeq) {
        snap.loading = false;
        loadStartedAt = null;
        final pending = pendingBounds;
        pendingBounds = null;
        if (pending != null && _isEnabled()) {
          await load(pending);
        } else if (_isFieldMode() && _isEnabled()) {
          _notifyChanged();
        }
      }
    }
  }
}
