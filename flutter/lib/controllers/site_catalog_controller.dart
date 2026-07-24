import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
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
  final Random _random = Random();

  List<SiteSummary> _rawItems = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _seed;
  int _loadSeq = 0;
  int _offset = 0;
  bool _hasMore = false;
  int _total = 0;
  SiteMapFilters _filters = SiteMapFilters();

  /// Visible catalog rows after applying client-side period/rock/status filters.
  @override
  List<SiteSummary> get items {
    if (!_needsClientMatch) {
      return List.unmodifiable(_rawItems);
    }
    return List.unmodifiable(_rawItems.where(_filters.matches));
  }

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
        _filters.discoveryTimeActive;
  }

  @override
  bool get loading => _loading;
  @override
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  @override
  String? get error => _error;
  @override
  bool get isEmpty =>
      !_loading && !_loadingMore && _error == null && items.isEmpty;
  int get total => _total;
  SiteMapFilters get filters => _filters;
  @override
  bool get hasActiveFilters => _filters.hasActiveFilters;

  LatLng? get currentLocation => _locationService?.currentLocation;

  CatalogDataSource get _dataSource =>
      _catalogModeController?.dataSource ?? CatalogDataSource.archive;

  bool get _isFieldMode => _dataSource == CatalogDataSource.field;

  Future<void> load({bool force = false}) async {
    if (!force && _rawItems.isNotEmpty) return;

    final seq = ++_loadSeq;
    final keepExistingItems = force && _rawItems.isNotEmpty;

    _loading = true;
    _error = null;
    _seed = _newSeed();
    _offset = 0;
    _hasMore = false;
    _filters = _filters.copyWith(filterByStatus: _isFieldMode);
    if (!keepExistingItems) {
      _rawItems = [];
      _total = 0;
    }
    notifyListeners();

    var loadedOk = false;
    try {
      final response = await _fetchPage(offset: 0);
      if (seq != _loadSeq) return;
      _rawItems = response.items;
      _offset = response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
      loadedOk = true;
      if (kDebugMode) {
        final preview = _rawItems.take(5).map((s) => s.displayTitle).join(', ');
        debugPrint(
          'SiteCatalogController: loaded ${_rawItems.length}/$_total sites '
          '(sort=${_filters.sort.apiValue}, seed=$_seed) → $preview',
        );
      }
    } on SiteServiceException catch (error) {
      if (seq != _loadSeq) return;
      _error = error.message;
    } catch (error) {
      if (seq != _loadSeq) return;
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('SiteCatalogController.load failed: $error');
      }
    } finally {
      if (seq == _loadSeq) {
        _loading = false;
        notifyListeners();
      }
    }

    if (loadedOk && seq == _loadSeq) {
      await _fillUntil(seq, minVisible: pageSize);
    }
  }

  @override
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;

    if (_needsClientMatch) {
      final before = items.length;
      await _fillUntil(_loadSeq, minVisible: before + 1);
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
    while (seq == _loadSeq &&
        _hasMore &&
        _error == null &&
        items.length < minVisible) {
      final before = _rawItems.length;
      await _fetchNextPage();
      if (seq != _loadSeq) return;
      if (_rawItems.length == before) return;
    }
  }

  Future<void> _fetchNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (_filters.sort == SiteCatalogSort.random && _seed == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      final response = await _fetchPage(offset: _offset);
      _rawItems = [..._rawItems, ...response.items];
      _offset += response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
    } on SiteServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('SiteCatalogController.loadMore failed: $error');
      }
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  void replaceSite(SiteSummary site) {
    final index = _rawItems.indexWhere((item) => item.siteId == site.siteId);
    if (index < 0) return;
    final updated = [..._rawItems];
    updated[index] = site;
    _rawItems = updated;
    notifyListeners();
  }

  /// Insert or replace a site after discovery without a full catalog reload.
  void upsertSite(SiteSummary site) {
    final index = _rawItems.indexWhere((item) => item.siteId == site.siteId);
    if (index < 0) {
      _rawItems = [site, ..._rawItems];
      _total += 1;
    } else {
      final updated = [..._rawItems];
      updated[index] = site;
      _rawItems = updated;
    }
    notifyListeners();
  }

  Future<SiteListResponse> _fetchPage({required int offset}) async {
    final sort = _filters.sort;
    if (sort == SiteCatalogSort.random) {
      final seed = _seed;
      if (seed == null || seed.isEmpty) {
        throw StateError('Catalog seed missing before fetch');
      }
    }

    final origin = _locationService?.currentLocation;
    final how = _filters.howDiscoveredActive
        ? _filters.howDiscovered.toList()
        : null;
    final after =
        _filters.discoveryTimeActive ? _filters.discoveredAfter : null;
    final before =
        _filters.discoveryTimeActive ? _filters.discoveredBefore : null;

    return _service.fetchSites(
      limit: pageSize,
      offset: offset,
      sort: sort.apiValue,
      seed: sort == SiteCatalogSort.random ? _seed : null,
      dataSource: _dataSource,
      howDiscovered: how,
      discoveredAfter: after,
      discoveredBefore: before,
      lat: sort == SiteCatalogSort.distance ? origin?.latitude : null,
      lon: sort == SiteCatalogSort.distance ? origin?.longitude : null,
    );
  }

  String _newSeed() {
    return '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
