import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/geologic_timeline_constants.dart';
import '../models/dinosaur.dart';
import '../services/dinosaur_service.dart';
import 'catalog_controller.dart';

enum DinoScreenMode { catalog, inventory }

/// Canonical diet values from enrichment (empty selection = all).
const dinosaurDietFilterOptions = <String>[
  'herbivore',
  'carnivore',
  'omnivore',
  'piscivore',
  'insectivore',
  'filter-feeder',
  'unknown',
];

const lengthMMinBound = 0.0;
const lengthMMaxBound = 40.0;
const massKgMinBound = 0.0;
const massKgMaxBound = 100000.0; // 100 t
const massTMinBound = 0.0;
const massTMaxBound = 100.0;

class DinosaurCatalogFilters {
  const DinosaurCatalogFilters({
    this.searchQuery = '',
    this.maYounger = mesozoicYoungerMa,
    this.maOlder = mesozoicOlderMa,
    this.diets = const {},
    this.lengthMMin = lengthMMinBound,
    this.lengthMMax = lengthMMaxBound,
    this.massKgMin = massKgMinBound,
    this.massKgMax = massKgMaxBound,
  });

  final String searchQuery;
  final double maYounger;
  final double maOlder;
  final Set<String> diets;
  final double lengthMMin;
  final double lengthMMax;
  final double massKgMin;
  final double massKgMax;

  bool get hasActiveFilters {
    if (searchQuery.trim().isNotEmpty) return true;
    if (diets.isNotEmpty) return true;
    if (hasLengthFilter) return true;
    if (hasMassFilter) return true;
    return hasTimeFilter;
  }

  bool get hasTimeFilter =>
      maYounger > mesozoicYoungerMa || maOlder < mesozoicOlderMa;

  bool get hasLengthFilter =>
      lengthMMin > lengthMMinBound || lengthMMax < lengthMMaxBound;

  bool get hasMassFilter =>
      massKgMin > massKgMinBound || massKgMax < massKgMaxBound;

  double get massTMin => massKgMin / 1000.0;
  double get massTMax => massKgMax / 1000.0;

  DinosaurCatalogFilters copyWith({
    String? searchQuery,
    double? maYounger,
    double? maOlder,
    Set<String>? diets,
    double? lengthMMin,
    double? lengthMMax,
    double? massKgMin,
    double? massKgMax,
  }) {
    return DinosaurCatalogFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      maYounger: maYounger ?? this.maYounger,
      maOlder: maOlder ?? this.maOlder,
      diets: diets ?? this.diets,
      lengthMMin: lengthMMin ?? this.lengthMMin,
      lengthMMax: lengthMMax ?? this.lengthMMax,
      massKgMin: massKgMin ?? this.massKgMin,
      massKgMax: massKgMax ?? this.massKgMax,
    );
  }

  static const defaults = DinosaurCatalogFilters();
}

class DinosaurCatalogController extends CatalogController<DinosaurSummary> {
  DinosaurCatalogController({DinosaurService? service})
    : _service = service ?? DinosaurService();

  static const pageSize = 20;

  final DinosaurService _service;
  final Random _random = Random();

  String? _seed;
  DinosaurCatalogFilters _filters = DinosaurCatalogFilters.defaults;
  DinoScreenMode _mode = DinoScreenMode.inventory;

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
      canProceed: () => _filters.searchQuery.trim().isNotEmpty || _seed != null,
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
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final seed = _seed;
    if (!hasSearch && (seed == null || seed.isEmpty)) {
      throw StateError('Catalog seed missing before fetch');
    }
    return _service.fetchDinosaurs(
      limit: pageSize,
      offset: offset,
      sort: hasSearch ? 'name' : 'random',
      seed: hasSearch ? null : seed,
      q: hasSearch ? _filters.searchQuery.trim() : null,
      maYounger: !hasSearch && _filters.hasTimeFilter
          ? _filters.maYounger
          : null,
      maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
      diets: _filters.diets,
      lengthMMin: _filters.hasLengthFilter ? _filters.lengthMMin : null,
      lengthMMax: _filters.hasLengthFilter ? _filters.lengthMMax : null,
      massKgMin: _filters.hasMassFilter ? _filters.massKgMin : null,
      massKgMax: _filters.hasMassFilter ? _filters.massKgMax : null,
      mode: _mode == DinoScreenMode.inventory ? 'inventory' : 'catalog',
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

  /// Remove an inventory occurrence after throw-away.
  void removeDinosaur(int dinosaurId) {
    final index = catalogItems.indexWhere((item) => item.id == dinosaurId);
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
