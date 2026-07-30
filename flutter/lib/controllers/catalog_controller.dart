import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Shared shape of the dino/fossil/site/tool catalog controllers, so
/// [CatalogListScreen] can drive paging, refresh, and empty/error states
/// without knowing about any specific catalog domain.
///
/// Also owns the common pagination / soft-refresh / load-sequence state that
/// every concrete catalog previously duplicated.
abstract class CatalogController<T> extends ChangeNotifier {
  List<T> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _loadSeq = 0;
  int _offset = 0;
  bool _hasMore = false;
  int _total = 0;

  List<T> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;
  int get total => _total;
  bool get hasActiveFilters;

  Future<void> refresh();
  Future<void> loadMore();

  // --- Protected storage for subclasses (e.g. site client-side filtering) ---

  @protected
  List<T> get catalogItems => _items;

  @protected
  set catalogItems(List<T> value) => _items = value;

  @protected
  int get catalogOffset => _offset;

  @protected
  bool get catalogHasMore => _hasMore;

  @protected
  int get catalogTotal => _total;

  @protected
  set catalogTotal(int value) => _total = value;

  @protected
  String? get catalogError => _error;

  @protected
  int get loadSeq => _loadSeq;

  /// Shared unreachable-API copy used by all catalogs.
  @protected
  String get apiUnreachableMessage =>
      'Could not reach the API at ${AppConfig.baseApiUrl}. '
      'Check your connection or try again later.';

  @protected
  String newCatalogSeed(Random random) =>
      '${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';

  /// Soft-refresh gate + sequence bump. Returns null when load should be skipped.
  @protected
  int? beginLoadSequence({required bool force}) {
    if (!force && _items.isNotEmpty) return null;
    return ++_loadSeq;
  }

  @protected
  bool isCurrentLoad(int seq) => seq == _loadSeq;

  /// Sets loading/error/offset/hasMore and optionally clears items (soft refresh).
  @protected
  void preparePrimaryLoad({required bool keepExistingItems}) {
    _loading = true;
    _error = null;
    _offset = 0;
    _hasMore = false;
    if (!keepExistingItems) {
      _items = [];
      _total = 0;
    }
    notifyListeners();
  }

  @protected
  void replaceCatalogPage({
    required List<T> items,
    required bool hasMore,
    required int total,
  }) {
    _items = items;
    _offset = items.length;
    _hasMore = hasMore;
    _total = total;
    _error = null;
  }

  @protected
  void appendCatalogPage({
    required List<T> items,
    required bool hasMore,
    required int total,
  }) {
    _items = [..._items, ...items];
    _offset += items.length;
    _hasMore = hasMore;
    _total = total;
    _error = null;
  }

  @protected
  void setCatalogError(String message) {
    _error = message;
  }

  @protected
  void finishPrimaryLoad(int seq) {
    if (seq == _loadSeq) {
      _loading = false;
      notifyListeners();
    }
  }

  /// Starts load-more UI state. Returns false if paging should not proceed.
  @protected
  bool beginLoadMore({bool Function()? canProceed}) {
    if (_loading || _loadingMore || !_hasMore) return false;
    if (canProceed != null && !canProceed()) return false;
    _loadingMore = true;
    notifyListeners();
    return true;
  }

  @protected
  void finishLoadMore() {
    _loadingMore = false;
    notifyListeners();
  }
}
