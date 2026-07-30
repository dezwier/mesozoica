import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/tool.dart';
import '../services/tool_service.dart';
import '../utils/curated_image_url.dart';
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

  List<ToolCategoryOption> _availableCategories = [];
  String? _seed;
  String? _chromeImageUrl;
  ToolCatalogFilters _filters = ToolCatalogFilters.defaults;
  ToolScreenMode _mode = ToolScreenMode.inventory;
  bool? _categoriesShowAll;

  List<ToolCategoryOption> get availableCategories =>
      List.unmodifiable(_availableCategories);
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
    final seq = beginLoadSequence(force: force);
    if (seq == null) return;

    final keepExistingItems = force && catalogItems.isNotEmpty;
    final useSeed = _filters.sort == ToolCatalogSort.category;

    if (useSeed) {
      _seed = newCatalogSeed(_random);
    }
    preparePrimaryLoad(keepExistingItems: keepExistingItems);

    try {
      final results = await Future.wait([
        _fetchPage(offset: 0),
        _ensureCategoriesLoaded(force: true),
      ]);
      if (!isCurrentLoad(seq)) return;
      final response = results[0] as ToolListResponse;
      replaceCatalogPage(
        items: response.items,
        hasMore: response.hasMore,
        total: response.total,
      );
      _maybePickChromeImage();
      if (kDebugMode) {
        final preview = catalogItems.take(5).map((t) => t.name).join(', ');
        debugPrint(
          'ToolCatalogController: loaded ${catalogItems.length}/$total tools '
          '(sort=${_filters.sort.apiValue}, showAll=${_filters.showAll}, '
          'seed=$_seed) → $preview',
        );
      }
    } on ToolServiceException catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(error.message);
    } catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('ToolCatalogController.load failed: $error');
      }
    } finally {
      finishPrimaryLoad(seq);
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
        seed: newCatalogSeed(_random),
        hasCustomImage: true,
        showAll: _filters.showAll,
        mode: _mode == ToolScreenMode.catalog ? 'catalog' : 'inventory',
      );
      final curated = response.items
          .map((tool) => tool.mainImageUrl)
          .where(isCuratedToolImageUrl)
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
    if (!beginLoadMore(
      canProceed: () =>
          !(_filters.sort == ToolCatalogSort.category && _seed == null),
    )) {
      return;
    }

    try {
      final response = await _fetchPage(offset: catalogOffset);
      appendCatalogPage(
        items: response.items,
        hasMore: response.hasMore,
        total: response.total,
      );
      _maybePickChromeImage();
    } on ToolServiceException catch (error) {
      setCatalogError(error.message);
    } catch (error) {
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('ToolCatalogController.loadMore failed: $error');
      }
    } finally {
      finishLoadMore();
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
    final index = catalogItems.indexWhere((item) => item.id == toolId);
    if (index >= 0) {
      final next = [...catalogItems];
      next[index] = updated;
      catalogItems = next;
      notifyListeners();
    }
    return updated;
  }

  /// Replace a single card in-memory without reloading the whole catalog.
  void replaceToolSummary(ToolSummary updated) {
    final index = catalogItems.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      final next = [...catalogItems];
      next[index] = updated;
      catalogItems = next;
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
    final curated = catalogItems
        .map((tool) => tool.mainImageUrl)
        .where(isCuratedToolImageUrl)
        .cast<String>()
        .toList(growable: false);
    if (curated.isEmpty) return;
    _chromeImageUrl = curated[_random.nextInt(curated.length)];
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
