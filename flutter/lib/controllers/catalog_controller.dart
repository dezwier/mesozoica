import 'package:flutter/foundation.dart';

/// Shared shape of the dino/fossil/site/tool catalog controllers, so
/// [CatalogListScreen] can drive paging, refresh, and empty/error states
/// without knowing about any specific catalog domain.
abstract class CatalogController<T> extends ChangeNotifier {
  List<T> get items;
  bool get loading;
  bool get isLoadingMore;
  String? get error;
  bool get isEmpty;
  bool get hasActiveFilters;

  Future<void> refresh();
  Future<void> loadMore();
}
