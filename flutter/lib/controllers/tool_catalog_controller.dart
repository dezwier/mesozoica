import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/tool.dart';
import '../services/tool_service.dart';
import '../widgets/cards/tool_card_image.dart';

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

class ToolCatalogFilters {
  const ToolCatalogFilters({
    this.searchQuery = '',
    this.sort = ToolCatalogSort.category,
    this.categories = const {},
  });

  final String searchQuery;
  final ToolCatalogSort sort;
  final Set<String> categories;

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty ||
      sort != ToolCatalogSort.category ||
      categories.isNotEmpty;

  ToolCatalogFilters copyWith({
    String? searchQuery,
    ToolCatalogSort? sort,
    Set<String>? categories,
  }) {
    return ToolCatalogFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      categories: categories ?? this.categories,
    );
  }

  static const defaults = ToolCatalogFilters();
}

class ToolCatalogController extends ChangeNotifier {
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

  List<ToolSummary> get items => List.unmodifiable(_items);
  List<ToolCategoryOption> get availableCategories =>
      List.unmodifiable(_availableCategories);
  bool get loading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;
  int get total => _total;
  ToolCatalogFilters get filters => _filters;
  bool get hasActiveFilters => _filters.hasActiveFilters;
  String? get chromeImageUrl => _chromeImageUrl;

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
        _ensureCategoriesLoaded(),
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
          '(sort=${_filters.sort.apiValue}, seed=$_seed) → $preview',
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

  Future<void> refresh() => load(force: true);

  Future<void> applyFilters(ToolCatalogFilters filters) async {
    _filters = filters;
    await load(force: true);
  }

  Future<void> clearFilters() async {
    _filters = ToolCatalogFilters.defaults;
    await load(force: true);
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
    );
  }

  Future<void> _ensureCategoriesLoaded() async {
    if (_availableCategories.isNotEmpty) return;
    try {
      _availableCategories = await _service.fetchCategories();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'ToolCatalogController: failed to load categories: $error',
        );
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
