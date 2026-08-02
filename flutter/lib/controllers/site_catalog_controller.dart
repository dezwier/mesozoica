import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/catalog_mode_controller.dart';
import '../models/site.dart';
import '../models/site_map_filters.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';
import 'catalog_controller.dart';

class SiteCatalogController extends CatalogController<SiteSummary> {
  SiteCatalogController({
    SiteService? service,
    CatalogModeController? catalogModeController,
    LocationService? locationService,
  })  : _service = service ?? SiteService(),
        _catalogModeController = catalogModeController,
        _locationService = locationService;

  static const pageSize = 20;

  final SiteService _service;
  final CatalogModeController? _catalogModeController;
  final LocationService? _locationService;

  SiteMapFilters _filters = SiteMapFilters();

  /// Visible catalog rows after applying client-side period/rock/status filters.
  @override
  List<SiteSummary> get items {
    if (!_needsClientMatch) {
      return List.unmodifiable(catalogItems);
    }
    return List.unmodifiable(catalogItems.where(_filters.matches));
  }

  /// Oldest discovery among loaded (unfiltered) catalog pages.
  DateTime? get earliestDiscovery => earliestSiteDiscovery(catalogItems);

  /// Period/rock/status still filter client-side; discovery is also matched
  /// client-side as a safety net (and for empty checkbox groups).
  bool get _needsClientMatch {
    final periodActive = _filters.periods.length != sitePeriodOptions.length;
    final rockActive = _filters.rockTypes.length != siteRockTypeOptions.length;
    final statusActive = _filters.filterByStatus &&
        _filters.statuses.length != siteStatusOptions.length;
    return periodActive ||
        rockActive ||
        statusActive ||
        _filters.howDiscoveredActive ||
        _filters.discoveryTimeActive();
  }

  @override
  bool get isEmpty =>
      !loading && !isLoadingMore && error == null && items.isEmpty;
  SiteMapFilters get filters => _filters;
  @override
  bool get hasActiveFilters => _filters.hasActiveFilters;

  LatLng? get currentLocation => _locationService?.currentLocation;

  CatalogDataSource get _dataSource =>
      _catalogModeController?.dataSource ?? CatalogDataSource.archive;

  bool get _isFieldMode => _dataSource == CatalogDataSource.field;

  Future<void> load({bool force = false}) async {
    final seq = beginLoadSequence(force: force);
    if (seq == null) return;

    final keepExistingItems = force && catalogItems.isNotEmpty;

    _filters = _filters.copyWith(filterByStatus: _isFieldMode);
    preparePrimaryLoad(keepExistingItems: keepExistingItems);

    var loadedOk = false;
    try {
      final response = await _fetchPage(offset: 0);
      if (!isCurrentLoad(seq)) return;
      replaceCatalogPage(
        items: response.items,
        hasMore: response.hasMore,
        total: response.total,
      );
      loadedOk = true;
      if (kDebugMode) {
        final preview =
            catalogItems.take(5).map((s) => s.displayTitle).join(', ');
        debugPrint(
          'SiteCatalogController: loaded ${catalogItems.length}/$total sites '
          '(sort=${_filters.sort.apiValue}) → $preview',
        );
      }
    } on SiteServiceException catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(error.message);
    } catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('SiteCatalogController.load failed: $error');
      }
    } finally {
      finishPrimaryLoad(seq);
    }

    if (loadedOk && isCurrentLoad(seq)) {
      await _fillUntil(seq, minVisible: pageSize);
    }
  }

  @override
  Future<void> loadMore() async {
    if (loading || isLoadingMore || !hasMore || error != null) return;

    if (_needsClientMatch) {
      final before = items.length;
      await _fillUntil(loadSeq, minVisible: before + 1);
      return;
    }

    await _fetchNextPage();
  }

  @override
  Future<void> refresh() => load(force: true);

  void applyFilters(SiteMapFilters filters) {
    _filters = filters.copyWith(filterByStatus: _isFieldMode);
    notifyListeners();
    // Discovery filters + sort are server-backed; always reload.
    unawaited(load(force: true));
  }

  /// Keep paging until [items] reaches [minVisible] or the catalog is exhausted.
  Future<void> _fillUntil(int seq, {required int minVisible}) async {
    if (!_needsClientMatch) return;
    while (isCurrentLoad(seq) &&
        catalogHasMore &&
        catalogError == null &&
        items.length < minVisible) {
      final before = catalogItems.length;
      await _fetchNextPage();
      if (!isCurrentLoad(seq)) return;
      if (catalogItems.length == before) return;
    }
  }

  Future<void> _fetchNextPage() async {
    if (!beginLoadMore()) return;

    try {
      final response = await _fetchPage(offset: catalogOffset);
      appendCatalogPage(
        items: response.items,
        hasMore: response.hasMore,
        total: response.total,
      );
    } on SiteServiceException catch (error) {
      setCatalogError(error.message);
    } catch (error) {
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('SiteCatalogController.loadMore failed: $error');
      }
    } finally {
      finishLoadMore();
    }
  }

  void replaceSite(SiteSummary site) {
    final index =
        catalogItems.indexWhere((item) => item.siteId == site.siteId);
    if (index < 0) return;
    final updated = [...catalogItems];
    updated[index] = site;
    catalogItems = updated;
    notifyListeners();
  }

  /// Remove a field site after throw-away.
  void removeSite(int siteId) {
    final index = catalogItems.indexWhere((item) => item.siteId == siteId);
    if (index < 0) return;
    catalogItems = [...catalogItems]..removeAt(index);
    if (catalogTotal > 0) catalogTotal = catalogTotal - 1;
    notifyListeners();
  }

  /// Insert or replace a site after discovery without a full catalog reload.
  void upsertSite(SiteSummary site) {
    final index =
        catalogItems.indexWhere((item) => item.siteId == site.siteId);
    if (index < 0) {
      catalogItems = [site, ...catalogItems];
      catalogTotal = catalogTotal + 1;
    } else {
      final updated = [...catalogItems];
      updated[index] = site;
      catalogItems = updated;
    }
    notifyListeners();
  }

  Future<SiteListResponse> _fetchPage({required int offset}) async {
    var sort = _filters.sort;
    final origin = _locationService?.currentLocation;
    if (sort == SiteCatalogSort.distance && origin == null) {
      sort = SiteCatalogSort.discoveredAtDesc;
    }

    final how = _filters.howDiscoveredActive
        ? _filters.howDiscovered.toList()
        : null;
    final timeActive = _filters.discoveryTimeActive();
    final after = timeActive ? _filters.discoveredAfter : null;
    final before = timeActive ? _filters.discoveredBefore : null;

    return _service.fetchSites(
      limit: pageSize,
      offset: offset,
      sort: sort.apiValue,
      dataSource: _dataSource,
      howDiscovered: how,
      discoveredAfter: after,
      discoveredBefore: before,
      lat: sort == SiteCatalogSort.distance ? origin?.latitude : null,
      lon: sort == SiteCatalogSort.distance ? origin?.longitude : null,
    );
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
