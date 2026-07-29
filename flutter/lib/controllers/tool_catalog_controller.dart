import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/tool.dart';
import '../services/tool_service.dart';
import '../widgets/cards/tool_card_image.dart';
import 'catalog_controller.dart';

enum ToolCatalogSort {
  category,
  name;

  String get label => switch (this) {
    ToolCatalogSort.category => 'Category',
    ToolCatalogSort.name => 'A–Z',
  };

  String get apiValue => switch (this) {
    ToolCatalogSort.category => 'category',
    ToolCatalogSort.name => 'name',
  };

  static ToolCatalogSort fromApiValue(String value) {
    return switch (value) {
      'name' => ToolCatalogSort.name,
      _ => ToolCatalogSort.category,
    };
  }
}

enum ToolScreenMode { inventory, catalog }

class ToolCatalogFilters {
  const ToolCatalogFilters({
    this.searchQuery = '',
    this.sort = ToolCatalogSort.category,
    this.categories = const {},
    this.showAll = false,
  });

  final String searchQuery;
  final ToolCatalogSort sort;
  final Set<String> categories;
  final bool showAll;

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      sort != ToolCatalogSort.category ||
      categories.isNotEmpty;

  ToolCatalogFilters copyWith({
    String? searchQuery,
    ToolCatalogSort? sort,
    Set<String>? categories,
    bool? showAll,
  }) {
    return ToolCatalogFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      categories: categories ?? this.categories,
      showAll: showAll ?? this.showAll,
    );
  }

  static const defaults = ToolCatalogFilters();
}

class ToolCatalogController extends CatalogController<ToolSummary> {
  ToolCatalogController({ToolService? service})
    : _service = service ?? ToolService();

  static const pageSize = 20;

  final ToolService _service;
  final Random _random = Random();

  List<ToolSummary> _items = [];
  List<ToolCategoryOption> _availableCategories = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _seed;
  String? _chromeImageUrl;
  int _loadSeq = 0;
  int _offset = 0;
  bool _hasMore = false;
  int _total = 0;
  ToolCatalogFilters _filters = ToolCatalogFilters.defaults;
  ToolScreenMode _mode = ToolScreenMode.inventory;
  bool? _categoriesShowAll;

  @override
  List<ToolSummary> get items => List.unmodifiable(_items);
  List<ToolCategoryOption> get availableCategories =>
      List.unmodifiable(_availableCategories);
  @override
  bool get loading => _loading;
  @override
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  @override
  String? get error => _error;
  @override
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;
  int get total => _total;
  ToolCatalogFilters get filters => _filters;
  ToolScreenMode get mode => _mode;
  @override
  bool get hasActiveFilters => _filters.hasActiveFilters;
  bool get showAll => _filters.showAll;
  String? get chromeImageUrl => _chromeImageUrl;

  void setMode(ToolScreenMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _filters = _filters.copyWith(showAll: mode == ToolScreenMode.catalog);
    _availableCategories = [];
    _categoriesShowAll = null;
    load(force: true);
  }

  /// Kept for shell auth wiring; catalog is available to all users.
  void onUserChanged({required bool isAdmin}) {}


  Future<void> load({bool force = false}) async {
    if (!force && _items.isNotEmpty) return;

    final seq = ++_loadSeq;
    final keepExistingItems = force && _items.isNotEmpty;
    final useSeed = _filters.sort == ToolCatalogSort.category;

    _loading = true;
    _error = null;
    if (useSeed) {
      _seed = _newSeed();
    }
    _offset = 0;
    _hasMore = false;
    if (!keepExistingItems) {
      _items = [];
      _total = 0;
    }
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchPage(offset: 0),
        _ensureCategoriesLoaded(force: true),
      ]);
      if (seq != _loadSeq) return;
      final response = results[0] as ToolListResponse;
      _items = response.items;
      _offset = response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
      _maybePickChromeImage();
      if (kDebugMode) {
        final preview = _items.take(5).map((t) => t.name).join(', ');
        debugPrint(
          'ToolCatalogController: loaded ${_items.length}/$_total tools '
          '(sort=${_filters.sort.apiValue}, showAll=${_filters.showAll}, '
          'seed=$_seed) → $preview',
        );
      }
    } on ToolServiceException catch (error) {
      if (seq != _loadSeq) return;
      _error = error.message;
    } catch (error) {
      if (seq != _loadSeq) return;
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('ToolCatalogController.load failed: $error');
      }
    } finally {
      if (seq == _loadSeq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> ensureChromeImage() async {
    if (_chromeImageUrl != null) return;
    try {
      await _ensureCategoriesLoaded();
      if (_chromeImageUrl != null) return;
      final response = await _service.fetchTools(
        limit: 40,
        offset: 0,
        sort: 'category',
        seed: _newSeed(),
        hasCustomImage: true,
        showAll: _filters.showAll,
        mode: _mode == ToolScreenMode.catalog ? 'catalog' : 'inventory',
      );
      final curated = response.items
          .map((tool) => tool.mainImageUrl)
          .where(ToolCardImage.isCuratedCardImageUrl)
          .cast<String>()
          .toList(growable: false);
      if (curated.isEmpty) return;
      _chromeImageUrl = curated[_random.nextInt(curated.length)];
      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('ToolCatalogController.ensureChromeImage failed: $error');
      }
    }
  }

  @override
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (_filters.sort == ToolCatalogSort.category && _seed == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      final response = await _fetchPage(offset: _offset);
      _items = [..._items, ...response.items];
      _offset += response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
      _maybePickChromeImage();
    } on ToolServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('ToolCatalogController.loadMore failed: $error');
      }
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  @override
  Future<void> refresh() => load(force: true);

  Future<void> applyFilters(ToolCatalogFilters filters) async {
    final nextShowAll = _mode == ToolScreenMode.catalog;
    final showAllChanged = nextShowAll != _filters.showAll;
    _filters = filters.copyWith(showAll: nextShowAll);
    if (showAllChanged) {
      _availableCategories = [];
      _categoriesShowAll = null;
    }
    await load(force: true);
  }

  Future<void> clearFilters() async {
    _filters = ToolCatalogFilters.defaults.copyWith(
      showAll: _mode == ToolScreenMode.catalog,
    );
    _availableCategories = [];
    _categoriesShowAll = null;
    await load(force: true);
  }

  /// Admin collect: upsert ownership and update the in-memory card.
  Future<ToolSummary> collectTool(int toolId) async {
    final updated = await _service.collectTool(toolId);
    final index = _items.indexWhere((item) => item.id == toolId);
    if (index >= 0) {
      _items = [..._items];
      _items[index] = updated;
      notifyListeners();
    }
    return updated;
  }

  /// Replace a single card in-memory without reloading the whole catalog.
  void replaceToolSummary(ToolSummary updated) {
    final index = _items.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      _items = [..._items];
      _items[index] = updated;
      notifyListeners();
    }
  }

  Future<ToolListResponse> _fetchPage({required int offset}) async {
    final useSeed = _filters.sort == ToolCatalogSort.category;
    final seed = useSeed ? _seed : null;
    if (useSeed && (seed == null || seed.isEmpty)) {
      throw StateError('Catalog seed missing before fetch');
    }

    final trimmedQuery = _filters.searchQuery.trim();
    return _service.fetchTools(
      limit: pageSize,
      offset: offset,
      sort: _filters.sort.apiValue,
      seed: seed,
      q: trimmedQuery.isNotEmpty ? trimmedQuery : null,
      categories: _filters.categories,
      showAll: _filters.showAll,
      mode: _mode == ToolScreenMode.catalog ? 'catalog' : 'inventory',
    );
  }

  Future<void> _ensureCategoriesLoaded({bool force = false}) async {
    if (!force &&
        _availableCategories.isNotEmpty &&
        _categoriesShowAll == _filters.showAll) {
      return;
    }
    try {
      _availableCategories = await _service.fetchCategories(
        showAll: _filters.showAll,
        mode: _mode == ToolScreenMode.catalog ? 'catalog' : 'inventory',
      );
      _categoriesShowAll = _filters.showAll;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('ToolCatalogController: failed to load categories: $error');
      }
    }
  }

  void _maybePickChromeImage() {
    if (_chromeImageUrl != null) return;
    final curated = _items
        .map((tool) => tool.mainImageUrl)
        .where(ToolCardImage.isCuratedCardImageUrl)
        .cast<String>()
        .toList(growable: false);
    if (curated.isEmpty) return;
    _chromeImageUrl = curated[_random.nextInt(curated.length)];
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
