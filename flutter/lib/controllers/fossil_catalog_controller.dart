import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/geologic_timeline_constants.dart';
import '../controllers/catalog_mode_controller.dart';
import '../models/fossil.dart';
import '../services/fossil_service.dart';
import '../utils/curated_image_url.dart';
import 'catalog_controller.dart';

class FossilCatalogFilters {
  const FossilCatalogFilters({
    this.dinoSearchQuery = '',
    this.fossilSearchQuery = '',
    this.maYounger = mesozoicYoungerMa,
    this.maOlder = mesozoicOlderMa,
    this.onlyCustomFossilImage = false,
    this.onlyLlmEnriched = true,
  });

  final String dinoSearchQuery;
  final String fossilSearchQuery;
  final double maYounger;
  final double maOlder;
  final bool onlyCustomFossilImage;
  final bool onlyLlmEnriched;

  bool get hasSearch =>
      dinoSearchQuery.trim().isNotEmpty || fossilSearchQuery.trim().isNotEmpty;

  bool get hasActiveFilters {
    if (hasSearch) return true;
    if (onlyCustomFossilImage) return true;
    if (!onlyLlmEnriched) return true;
    return maYounger > mesozoicYoungerMa || maOlder < mesozoicOlderMa;
  }

  bool get hasTimeFilter =>
      maYounger > mesozoicYoungerMa || maOlder < mesozoicOlderMa;

  FossilCatalogFilters copyWith({
    String? dinoSearchQuery,
    String? fossilSearchQuery,
    double? maYounger,
    double? maOlder,
    bool? onlyCustomFossilImage,
    bool? onlyLlmEnriched,
  }) {
    return FossilCatalogFilters(
      dinoSearchQuery: dinoSearchQuery ?? this.dinoSearchQuery,
      fossilSearchQuery: fossilSearchQuery ?? this.fossilSearchQuery,
      maYounger: maYounger ?? this.maYounger,
      maOlder: maOlder ?? this.maOlder,
      onlyCustomFossilImage:
          onlyCustomFossilImage ?? this.onlyCustomFossilImage,
      onlyLlmEnriched: onlyLlmEnriched ?? this.onlyLlmEnriched,
    );
  }

  static const defaults = FossilCatalogFilters();
}

class FossilCatalogController extends CatalogController<FossilSummary> {
  FossilCatalogController({
    FossilService? service,
    CatalogModeController? catalogModeController,
  })  : _service = service ?? FossilService(),
        _catalogModeController = catalogModeController;

  static const pageSize = 20;
  static const _clientScanPageSize = 500;

  final FossilService _service;
  final CatalogModeController? _catalogModeController;
  final Random _random = Random();

  String? _seed;
  FossilCatalogFilters _filters = FossilCatalogFilters.defaults;
  bool _useClientCustomImageFilter = false;

  FossilCatalogFilters get filters => _filters;
  @override
  bool get hasActiveFilters {
    if (_dataSource == CatalogDataSource.field) {
      if (_filters.hasSearch) return true;
      if (_filters.onlyCustomFossilImage) return true;
      return _filters.hasTimeFilter;
    }
    return _filters.hasActiveFilters;
  }

  /// Archive catalog defaults to enriched fossils; field discoveries skip that.
  bool? get _llmEnrichedQuery {
    if (_dataSource == CatalogDataSource.field) return null;
    return _filters.onlyLlmEnriched ? true : null;
  }

  CatalogDataSource get _dataSource =>
      _catalogModeController?.dataSource ?? CatalogDataSource.archive;

  Future<void> load({bool force = false}) async {
    final seq = beginLoadSequence(force: force);
    if (seq == null) return;

    final keepExistingItems = force && catalogItems.isNotEmpty;
    final hasSearch = _filters.hasSearch;

    _useClientCustomImageFilter = false;
    if (!hasSearch) {
      _seed = newCatalogSeed(_random);
    }
    preparePrimaryLoad(keepExistingItems: keepExistingItems);

    try {
      final response = await _fetchPage(offset: 0);
      if (!isCurrentLoad(seq)) return;
      replaceCatalogPage(
        items: response.items,
        hasMore: response.hasMore,
        total: response.total,
      );
      if (kDebugMode) {
        final preview =
            catalogItems.take(5).map((f) => f.displayTitle).join(', ');
        debugPrint(
          'FossilCatalogController: loaded ${catalogItems.length}/$total fossils '
          '(sort=${hasSearch ? 'name' : 'random'}, seed=$_seed) → $preview',
        );
      }
    } on FossilServiceException catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(error.message);
    } catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('FossilCatalogController.load failed: $error');
      }
    } finally {
      finishPrimaryLoad(seq);
    }
  }

  @override
  Future<void> loadMore() async {
    if (!beginLoadMore(
      canProceed: () => !_useClientCustomImageFilter && _seed != null,
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
    } on FossilServiceException catch (error) {
      setCatalogError(error.message);
    } catch (error) {
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('FossilCatalogController.loadMore failed: $error');
      }
    } finally {
      finishLoadMore();
    }
  }

  @override
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
    if (_filters.onlyCustomFossilImage && _useClientCustomImageFilter) {
      return _fetchAllCuratedClientSide();
    }

    final hasSearch = _filters.hasSearch;
    final seed = _seed;
    if (!hasSearch && (seed == null || seed.isEmpty)) {
      throw StateError('Catalog seed missing before fetch');
    }
    final response = await _service.fetchFossils(
      limit: pageSize,
      offset: offset,
      sort: hasSearch ? 'name' : 'random',
      seed: hasSearch ? null : seed,
      dinoQ: hasSearch ? _filters.dinoSearchQuery.trim() : null,
      fossilQ: hasSearch ? _filters.fossilSearchQuery.trim() : null,
      maYounger:
          !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
      maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
      hasCustomFossilImage: _filters.onlyCustomFossilImage,
      llmEnriched: _llmEnrichedQuery,
      dataSource: _dataSource,
    );

    if (_filters.onlyCustomFossilImage &&
        offset == 0 &&
        !_serverHonorsCustomImageFilter(response)) {
      _useClientCustomImageFilter = true;
      if (kDebugMode) {
        debugPrint(
          'FossilCatalogController: API ignored has_custom_fossil_image; '
          'scanning catalog client-side',
        );
      }
      return _fetchAllCuratedClientSide();
    }

    return response;
  }

  bool _serverHonorsCustomImageFilter(FossilListResponse response) {
    return !response.items.any(
      (fossil) => !isCuratedFossilImageUrl(fossil.mainImageUrl),
    );
  }

  Future<FossilListResponse> _fetchAllCuratedClientSide() async {
    final hasSearch = _filters.hasSearch;
    final seed = _seed ?? newCatalogSeed(_random);
    final curated = <FossilSummary>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _service.fetchFossils(
        limit: _clientScanPageSize,
        offset: offset,
        sort: hasSearch ? 'name' : 'random',
        seed: hasSearch ? null : seed,
        dinoQ: hasSearch ? _filters.dinoSearchQuery.trim() : null,
        fossilQ: hasSearch ? _filters.fossilSearchQuery.trim() : null,
        maYounger:
            !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
        maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
        llmEnriched: _llmEnrichedQuery,
        dataSource: _dataSource,
      );
      curated.addAll(
        response.items.where(
          (fossil) => isCuratedFossilImageUrl(fossil.mainImageUrl),
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

  /// Update or remove a fossil after an admin status change.
  void replaceFossil(FossilSummary fossil) {
    final index = catalogItems.indexWhere((item) => item.id == fossil.id);
    if (index < 0) return;
    if (fossil.isHidden) {
      final updated = [...catalogItems]..removeAt(index);
      catalogItems = updated;
      if (catalogTotal > 0) catalogTotal = catalogTotal - 1;
    } else {
      final updated = [...catalogItems];
      updated[index] = fossil;
      catalogItems = updated;
    }
    notifyListeners();
  }

  /// Remove a field fossil after throw-away.
  void removeFossil(int fossilId) {
    final index = catalogItems.indexWhere((item) => item.id == fossilId);
    if (index < 0) return;
    catalogItems = [...catalogItems]..removeAt(index);
    if (catalogTotal > 0) catalogTotal = catalogTotal - 1;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
