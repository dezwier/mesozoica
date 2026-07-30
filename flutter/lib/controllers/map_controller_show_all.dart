part of 'map_controller.dart';

/// On-demand admin show-all: paginate the viewport bbox and replace markers.
extension _MapControllerShowAll on MapController {
  /// On-demand show-all: paginate the viewport bbox (API max 500/page) and
  /// replace markers once. Refuse when [MapConfig.showAllMaxSites] is exceeded.
  Future<ShowAllLoadResult> _loadShowAllPages(
    int seq,
    LatLngBounds bounds,
  ) async {
    final snap = _snapshots[_MapCacheKey.fieldShowAll]!;
    var result = ShowAllLoadResult.failed;
    try {
      if (seq != snap.loadSeq || !_showAllFieldSites) {
        return ShowAllLoadResult.cancelled;
      }

      // sort=name + LIMIT is a cheap SQL page. Avoid sort=distance here: the
      // backend loads the full bbox into memory to rank, which times out on
      // dense field tiles and leaves the toggle looking like a no-op.
      final allGeo = <SiteSummary>[];
      var offset = 0;
      var total = 0;
      var hasMore = true;

      while (hasMore) {
        if (seq != snap.loadSeq || !_showAllFieldSites) {
          return ShowAllLoadResult.cancelled;
        }

        final response = await _service.fetchSites(
          limit: MapController.pageSize,
          offset: offset,
          sort: 'name',
          dataSource: CatalogDataSource.field,
          showAll: true,
          minLat: bounds.south,
          maxLat: bounds.north,
          minLon: bounds.west,
          maxLon: bounds.east,
        );
        if (seq != snap.loadSeq || !_showAllFieldSites) {
          return ShowAllLoadResult.cancelled;
        }

        total = response.total;
        if (total > MapConfig.showAllMaxSites) {
          _showAllAuthoritative = false;
          snap.geoSites = [];
          snap.siteBounds = null;
          snap.loadedCatalog = 0;
          snap.totalCatalog = total;
          snap.maxFieldSiteId = 0;
          snap.error =
              'Too many sites in this view ($total). '
              'Zoom in and try again (max ${MapConfig.showAllMaxSites}).';
          snap.loadingComplete = false;
          result = ShowAllLoadResult.tooMany;
          return result;
        }

        final geo = _withCoordinates(response.items);
        allGeo.addAll(geo);
        offset += response.items.length;
        hasMore = response.hasMore &&
            response.items.isNotEmpty &&
            allGeo.length < total;
      }

      if (seq != snap.loadSeq || !_showAllFieldSites) {
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
      _showAllAuthoritative = true;
      result = ShowAllLoadResult.success;

      if (kDebugMode) {
        debugPrint(
          'MapController: show-all viewport — ${allGeo.length} markers '
          '(${snap.loadedCatalog}/${snap.totalCatalog} in bbox, '
          'show_all authoritative)',
        );
      }

      if (_isFieldMode && _showAllFieldSites) {
        notifyListeners();
      }
      return result;
    } on SiteServiceException catch (error) {
      if (seq != snap.loadSeq) return ShowAllLoadResult.cancelled;
      _showAllAuthoritative = false;
      snap.error = error.message;
      snap.loadingComplete = false;
      result = ShowAllLoadResult.failed;
      return result;
    } on TimeoutException catch (error) {
      if (seq != snap.loadSeq) return ShowAllLoadResult.cancelled;
      _showAllAuthoritative = false;
      snap.loadingComplete = false;
      final secs = error.duration?.inSeconds;
      snap.error = secs != null
          ? 'Timed out loading sites in view after ${secs}s — try again.'
          : 'Timed out loading sites in view — try again.';
      if (kDebugMode) {
        debugPrint('MapController.load show-all viewport timed out: $error');
      }
      result = ShowAllLoadResult.failed;
      return result;
    } catch (error) {
      if (seq != snap.loadSeq) return ShowAllLoadResult.cancelled;
      _showAllAuthoritative = false;
      snap.loadingComplete = false;
      snap.error = 'Could not load sites in view: $error';
      if (kDebugMode) {
        debugPrint('MapController.load show-all viewport failed: $error');
      }
      result = ShowAllLoadResult.failed;
      return result;
    } finally {
      if (seq == snap.loadSeq) {
        snap.loading = false;
        _showAllLoadStartedAt = null;
        final pending = _pendingShowAllBounds;
        _pendingShowAllBounds = null;
        if (pending != null && _showAllFieldSites) {
          await loadShowAllInBounds(pending);
        } else if (_isFieldMode && _showAllFieldSites) {
          notifyListeners();
        }
      }
    }
  }
}
