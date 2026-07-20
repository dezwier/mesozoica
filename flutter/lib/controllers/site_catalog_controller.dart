import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../controllers/catalog_mode_controller.dart';
import '../models/site.dart';
import '../services/site_service.dart';
import '../widgets/map/site_map_filters.dart';

class SiteCatalogController extends ChangeNotifier {
  SiteCatalogController({
    SiteService? service,
    CatalogModeController? catalogModeController,
  })  : _service = service ?? SiteService(),
        _catalogModeController = catalogModeController;

  static const pageSize = 20;

  final SiteService _service;
  final CatalogModeController? _catalogModeController;
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

  /// Visible catalog rows after applying [filters].
  List<SiteSummary> get items {
    if (!_filters.hasActiveFilters) {
      return List.unmodifiable(_rawItems);
    }
    return List.unmodifiable(_rawItems.where(_filters.matches));
  }

  bool get loading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isEmpty =>
      !_loading && !_loadingMore && _error == null && items.isEmpty;
  int get total => _total;
  SiteMapFilters get filters => _filters;
  bool get hasActiveFilters => _filters.hasActiveFilters;

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
          '(seed=$_seed) → $preview',
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

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (_seed == null) return;

    if (_filters.hasActiveFilters) {
      final before = items.length;
      await _fillUntil(_loadSeq, minVisible: before + 1);
      return;
    }

    await _fetchNextPage();
  }

  Future<void> refresh() => load(force: true);

  void applyFilters(SiteMapFilters filters) {
    _filters = filters.copyWith(filterByStatus: _isFieldMode);
    notifyListeners();
    unawaited(_fillUntil(_loadSeq, minVisible: pageSize));
  }

  /// Keep paging until [items] reaches [minVisible] or the catalog is exhausted.
  Future<void> _fillUntil(int seq, {required int minVisible}) async {
    if (!_filters.hasActiveFilters) return;
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
    if (_seed == null) return;

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

  Future<SiteListResponse> _fetchPage({required int offset}) async {
    final seed = _seed;
    if (seed == null || seed.isEmpty) {
      throw StateError('Catalog seed missing before fetch');
    }
    return _service.fetchSites(
      limit: pageSize,
      offset: offset,
      sort: 'random',
      seed: seed,
      dataSource: _dataSource,
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
