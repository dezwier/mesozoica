import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/tool.dart';
import '../services/tool_service.dart';

enum ToolCatalogSort {
  random,
  name,
  category;

  String get label => switch (this) {
        ToolCatalogSort.random => 'Random',
        ToolCatalogSort.name => 'A–Z',
        ToolCatalogSort.category => 'Category',
      };

  String get apiValue => switch (this) {
        ToolCatalogSort.random => 'random',
        ToolCatalogSort.name => 'name',
        ToolCatalogSort.category => 'category',
      };

  static ToolCatalogSort fromApiValue(String value) {
    return switch (value) {
      'name' => ToolCatalogSort.name,
      'category' => ToolCatalogSort.category,
      _ => ToolCatalogSort.random,
    };
  }
}

class ToolCatalogFilters {
  const ToolCatalogFilters({
    this.searchQuery = '',
    this.sort = ToolCatalogSort.random,
  });

  final String searchQuery;
  final ToolCatalogSort sort;

  bool get hasActiveFilters =>
      searchQuery.trim().isNotEmpty || sort != ToolCatalogSort.random;

  ToolCatalogFilters copyWith({
    String? searchQuery,
    ToolCatalogSort? sort,
  }) {
    return ToolCatalogFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
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
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _seed;
  int _loadSeq = 0;
  int _offset = 0;
  bool _hasMore = false;
  int _total = 0;
  ToolCatalogFilters _filters = ToolCatalogFilters.defaults;

  List<ToolSummary> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;
  int get total => _total;
  ToolCatalogFilters get filters => _filters;
  bool get hasActiveFilters => _filters.hasActiveFilters;

  Future<void> load({bool force = false}) async {
    if (!force && _items.isNotEmpty) return;

    final seq = ++_loadSeq;
    final keepExistingItems = force && _items.isNotEmpty;
    final useRandom = _filters.sort == ToolCatalogSort.random;

    _loading = true;
    _error = null;
    if (useRandom) {
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
      final response = await _fetchPage(offset: 0);
      if (seq != _loadSeq) return;
      _items = response.items;
      _offset = response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
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

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (_filters.sort == ToolCatalogSort.random && _seed == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      final response = await _fetchPage(offset: _offset);
      _items = [..._items, ...response.items];
      _offset += response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
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
    final useRandom = _filters.sort == ToolCatalogSort.random;
    final seed = useRandom ? _seed : null;
    if (useRandom && (seed == null || seed.isEmpty)) {
      throw StateError('Catalog seed missing before fetch');
    }

    final trimmedQuery = _filters.searchQuery.trim();
    return _service.fetchTools(
      limit: pageSize,
      offset: offset,
      sort: _filters.sort.apiValue,
      seed: seed,
      q: trimmedQuery.isNotEmpty ? trimmedQuery : null,
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
