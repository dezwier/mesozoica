import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/geologic_timeline_constants.dart';
import '../models/dinosaur.dart';
import '../services/dinosaur_service.dart';
import '../utils/curated_image_url.dart';
import 'catalog_controller.dart';

enum DinoScreenMode { catalog, inventory }

class DinosaurCatalogFilters {
  const DinosaurCatalogFilters({
    this.searchQuery = '',
    this.maYounger = mesozoicYoungerMa,
    this.maOlder = mesozoicOlderMa,
    this.onlyCustomImage = true,
    this.onlyLlmEnriched = true,
  });

  final String searchQuery;
  final double maYounger;
  final double maOlder;
  final bool onlyCustomImage;
  final bool onlyLlmEnriched;

  bool get hasActiveFilters {
    if (searchQuery.trim().isNotEmpty) return true;
    if (!onlyCustomImage) return true;
    if (!onlyLlmEnriched) return true;
    return maYounger > mesozoicYoungerMa || maOlder < mesozoicOlderMa;
  }

  bool get hasTimeFilter =>
      maYounger > mesozoicYoungerMa || maOlder < mesozoicOlderMa;

  DinosaurCatalogFilters copyWith({
    String? searchQuery,
    double? maYounger,
    double? maOlder,
    bool? onlyCustomImage,
    bool? onlyLlmEnriched,
  }) {
    return DinosaurCatalogFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      maYounger: maYounger ?? this.maYounger,
      maOlder: maOlder ?? this.maOlder,
      onlyCustomImage: onlyCustomImage ?? this.onlyCustomImage,
      onlyLlmEnriched: onlyLlmEnriched ?? this.onlyLlmEnriched,
    );
  }

  static const defaults = DinosaurCatalogFilters();
}

class DinosaurCatalogController extends CatalogController<DinosaurSummary> {
  DinosaurCatalogController({DinosaurService? service})
      : _service = service ?? DinosaurService();

  static const pageSize = 20;
  static const _clientScanPageSize = 500;

  final DinosaurService _service;
  final Random _random = Random();

  String? _seed;
  DinosaurCatalogFilters _filters = DinosaurCatalogFilters.defaults;
  DinoScreenMode _mode = DinoScreenMode.catalog;
  bool _useClientCustomImageFilter = false;

  DinosaurCatalogFilters get filters => _filters;
  DinoScreenMode get mode => _mode;
  @override
  bool get hasActiveFilters => _filters.hasActiveFilters;

  void setMode(DinoScreenMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    load(force: true);
  }

  Future<void> load({bool force = false}) async {
    final seq = beginLoadSequence(force: force);
    if (seq == null) return;

    final keepExistingItems = force && catalogItems.isNotEmpty;
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;

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
        final preview = catalogItems.take(5).map((d) => d.name).join(', ');
        debugPrint(
          'DinosaurCatalogController: loaded ${catalogItems.length}/$total dinos '
          '(sort=${hasSearch ? 'name' : 'random'}, seed=$_seed) → $preview',
        );
      }
    } on DinosaurServiceException catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(error.message);
    } catch (error) {
      if (!isCurrentLoad(seq)) return;
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('DinosaurCatalogController.load failed: $error');
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
    } on DinosaurServiceException catch (error) {
      setCatalogError(error.message);
    } catch (error) {
      setCatalogError(apiUnreachableMessage);
      if (kDebugMode) {
        debugPrint('DinosaurCatalogController.loadMore failed: $error');
      }
    } finally {
      finishLoadMore();
    }
  }

  @override
  Future<void> refresh() => load(force: true);

  Future<void> applyFilters(DinosaurCatalogFilters filters) async {
    _filters = filters;
    await load(force: true);
  }

  Future<void> clearFilters() async {
    _filters = DinosaurCatalogFilters.defaults;
    await load(force: true);
  }

  Future<DinosaurListResponse> _fetchPage({required int offset}) async {
    if (_filters.onlyCustomImage && _useClientCustomImageFilter) {
      return _fetchAllCuratedClientSide();
    }

    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final seed = _seed;
    if (!hasSearch && (seed == null || seed.isEmpty)) {
      throw StateError('Catalog seed missing before fetch');
    }
    final response = await _service.fetchDinosaurs(
      limit: pageSize,
      offset: offset,
      sort: hasSearch ? 'name' : 'random',
      seed: hasSearch ? null : seed,
      q: hasSearch ? _filters.searchQuery.trim() : null,
      maYounger:
          !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
      maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
      hasCustomImage: _filters.onlyCustomImage,
      llmEnriched: _filters.onlyLlmEnriched,
      mode: _mode == DinoScreenMode.inventory ? 'inventory' : 'catalog',
    );

    if (_filters.onlyCustomImage &&
        offset == 0 &&
        !_serverHonorsCustomImageFilter(response)) {
      _useClientCustomImageFilter = true;
      if (kDebugMode) {
        debugPrint(
          'DinosaurCatalogController: API ignored has_custom_image; '
          'scanning catalog client-side',
        );
      }
      return _fetchAllCuratedClientSide();
    }

    return response;
  }

  bool _serverHonorsCustomImageFilter(DinosaurListResponse response) {
    return !response.items.any(
      (dinosaur) =>
          !isCuratedDinosaurImageUrl(dinosaur.mainImageUrl),
    );
  }

  Future<DinosaurListResponse> _fetchAllCuratedClientSide() async {
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final seed = _seed ?? newCatalogSeed(_random);
    final curated = <DinosaurSummary>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _service.fetchDinosaurs(
        limit: _clientScanPageSize,
        offset: offset,
        sort: hasSearch ? 'name' : 'random',
        seed: hasSearch ? null : seed,
        q: hasSearch ? _filters.searchQuery.trim() : null,
        maYounger:
            !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
        maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
        llmEnriched: _filters.onlyLlmEnriched,
        mode: _mode == DinoScreenMode.inventory ? 'inventory' : 'catalog',
      );
      curated.addAll(
        response.items.where(
          (dinosaur) =>
              isCuratedDinosaurImageUrl(dinosaur.mainImageUrl),
        ),
      );
      offset += response.items.length;
      hasMore = response.hasMore;
      if (response.items.isEmpty) break;
    }

    if (!hasSearch && curated.length > 1) {
      curated.shuffle(_random);
    }

    return DinosaurListResponse(
      items: curated,
      total: curated.length,
      limit: curated.length,
      offset: 0,
      hasNext: false,
    );
  }

  /// Update a catalog dinosaur after an admin status change.
  void replaceDinosaur(DinosaurSummary dinosaur) {
    final typeId = dinosaur.dinosaurTypeId ?? dinosaur.id;
    final index = catalogItems.indexWhere(
      (item) => (item.dinosaurTypeId ?? item.id) == typeId,
    );
    if (index < 0) return;
    final updated = [...catalogItems];
    updated[index] = dinosaur;
    catalogItems = updated;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
