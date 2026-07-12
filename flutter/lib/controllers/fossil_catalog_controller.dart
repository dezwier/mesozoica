import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/fossil.dart';
import '../services/fossil_service.dart';
import '../widgets/cards/fossil_card_image.dart';
import '../widgets/cards/geologic_timeline.dart';

class FossilCatalogFilters {
  const FossilCatalogFilters({
    this.searchQuery = '',
    this.maYounger = GeologicTimeline.mesozoicYoungerMa,
    this.maOlder = GeologicTimeline.mesozoicOlderMa,
    this.onlyCustomImage = true,
  });

  final String searchQuery;
  final double maYounger;
  final double maOlder;
  final bool onlyCustomImage;

  bool get hasActiveFilters {
    if (searchQuery.trim().isNotEmpty) return true;
    if (!onlyCustomImage) return true;
    return maYounger > GeologicTimeline.mesozoicYoungerMa ||
        maOlder < GeologicTimeline.mesozoicOlderMa;
  }

  bool get hasTimeFilter =>
      maYounger > GeologicTimeline.mesozoicYoungerMa ||
      maOlder < GeologicTimeline.mesozoicOlderMa;

  FossilCatalogFilters copyWith({
    String? searchQuery,
    double? maYounger,
    double? maOlder,
    bool? onlyCustomImage,
  }) {
    return FossilCatalogFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      maYounger: maYounger ?? this.maYounger,
      maOlder: maOlder ?? this.maOlder,
      onlyCustomImage: onlyCustomImage ?? this.onlyCustomImage,
    );
  }

  static const defaults = FossilCatalogFilters();
}

class FossilCatalogController extends ChangeNotifier {
  FossilCatalogController({FossilService? service})
      : _service = service ?? FossilService();

  static const pageSize = 20;
  static const _clientScanPageSize = 500;

  final FossilService _service;
  final Random _random = Random();

  List<FossilSummary> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _seed;
  int _loadSeq = 0;
  int _offset = 0;
  bool _hasMore = false;
  int _total = 0;
  FossilCatalogFilters _filters = FossilCatalogFilters.defaults;
  bool _useClientCustomImageFilter = false;

  List<FossilSummary> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;
  int get total => _total;
  FossilCatalogFilters get filters => _filters;
  bool get hasActiveFilters => _filters.hasActiveFilters;

  Future<void> load({bool force = false}) async {
    if (!force && _items.isNotEmpty) return;

    final seq = ++_loadSeq;
    final keepExistingItems = force && _items.isNotEmpty;
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;

    _loading = true;
    _error = null;
    _useClientCustomImageFilter = false;
    if (!hasSearch) {
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
        final preview = _items.take(5).map((f) => f.displayTitle).join(', ');
        debugPrint(
          'FossilCatalogController: loaded ${_items.length}/$_total fossils '
          '(sort=${hasSearch ? 'name' : 'random'}, seed=$_seed) → $preview',
        );
      }
    } on FossilServiceException catch (error) {
      if (seq != _loadSeq) return;
      _error = error.message;
    } catch (error) {
      if (seq != _loadSeq) return;
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('FossilCatalogController.load failed: $error');
      }
    } finally {
      if (seq == _loadSeq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _useClientCustomImageFilter) {
      return;
    }
    if (_seed == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      final response = await _fetchPage(offset: _offset);
      _items = [..._items, ...response.items];
      _offset += response.items.length;
      _hasMore = response.hasMore;
      _total = response.total;
      _error = null;
    } on FossilServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('FossilCatalogController.loadMore failed: $error');
      }
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load(force: true);

  Future<void> applyFilters(FossilCatalogFilters filters) async {
    _filters = filters;
    await load(force: true);
  }

  Future<void> clearFilters() async {
    _filters = FossilCatalogFilters.defaults;
    await load(force: true);
  }

  Future<FossilListResponse> _fetchPage({required int offset}) async {
    if (_filters.onlyCustomImage && _useClientCustomImageFilter) {
      return _fetchAllCuratedClientSide();
    }

    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final seed = _seed;
    if (!hasSearch && (seed == null || seed.isEmpty)) {
      throw StateError('Catalog seed missing before fetch');
    }
    final response = await _service.fetchFossils(
      limit: pageSize,
      offset: offset,
      sort: hasSearch ? 'name' : 'random',
      seed: hasSearch ? null : seed,
      q: hasSearch ? _filters.searchQuery.trim() : null,
      maYounger:
          !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
      maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
      hasCustomImage: _filters.onlyCustomImage,
    );

    if (_filters.onlyCustomImage &&
        offset == 0 &&
        !_serverHonorsCustomImageFilter(response)) {
      _useClientCustomImageFilter = true;
      if (kDebugMode) {
        debugPrint(
          'FossilCatalogController: API ignored has_custom_image; '
          'scanning catalog client-side',
        );
      }
      return _fetchAllCuratedClientSide();
    }

    return response;
  }

  bool _serverHonorsCustomImageFilter(FossilListResponse response) {
    return !response.items.any(
      (fossil) => !FossilCardImage.isCuratedCardImageUrl(fossil.mainImageUrl),
    );
  }

  Future<FossilListResponse> _fetchAllCuratedClientSide() async {
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final curated = <FossilSummary>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _service.fetchFossils(
        limit: _clientScanPageSize,
        offset: offset,
        sort: 'name',
        q: hasSearch ? _filters.searchQuery.trim() : null,
        maYounger:
            !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
        maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
      );
      curated.addAll(
        response.items.where(
          (fossil) =>
              FossilCardImage.isCuratedCardImageUrl(fossil.mainImageUrl),
        ),
      );
      offset += response.items.length;
      hasMore = response.hasMore;
      if (response.items.isEmpty) break;
    }

    if (!hasSearch && curated.length > 1) {
      curated.shuffle(_random);
    }

    return FossilListResponse(
      items: curated,
      total: curated.length,
      limit: curated.length,
      offset: 0,
      hasNext: false,
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
