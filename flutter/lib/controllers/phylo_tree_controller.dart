import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../controllers/dinosaur_catalog_controller.dart';
import '../models/dinosaur.dart';
import '../models/phylo_tree.dart';
import '../services/dinosaur_service.dart';
import '../widgets/tree/fractal_tree_layout.dart';
import '../utils/phylo_tree_builder.dart';

class PhyloTreeController extends ChangeNotifier {
  PhyloTreeController({
    required DinosaurCatalogController catalogController,
    DinosaurService? service,
    PhyloTreeBuilder? builder,
  })  : _catalog = catalogController,
        _service = service ?? DinosaurService(),
        _builder = builder ?? const PhyloTreeBuilder() {
    _catalog.addListener(_onCatalogChanged);
  }

  static const _pageSize = 500;

  final DinosaurCatalogController _catalog;
  final DinosaurService _service;
  final PhyloTreeBuilder _builder;

  bool _loading = false;
  bool _loaded = false;
  String? _error;
  PhyloTreeNode? _root;
  FractalTreeLayout? _layout;
  int _placedCount = 0;
  int _unplacedCount = 0;
  int _totalGenera = 0;
  DinosaurCatalogFilters? _appliedFilters;

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  PhyloTreeNode? get root => _root;
  FractalTreeLayout? get layout => _layout;
  int get placedCount => _placedCount;
  int get unplacedCount => _unplacedCount;
  int get totalGenera => _totalGenera;
  DinosaurCatalogFilters get filters => _catalog.filters;
  bool get hasActiveFilters => _catalog.hasActiveFilters;

  void _onCatalogChanged() {
    if (!_loaded && !_loading) return;
    if (_appliedFilters != null &&
        _filtersEqual(_appliedFilters!, _catalog.filters)) {
      return;
    }
    reload();
  }

  Future<void> loadIfNeeded() async {
    if (_loading) return;
    if (_loaded &&
        _appliedFilters != null &&
        _filtersEqual(_appliedFilters!, _catalog.filters)) {
      return;
    }
    await reload();
  }

  Future<void> reload() async {
    _loading = true;
    _error = null;
    notifyListeners();

    final filters = _catalog.filters;

    try {
      final dinosaurs = await _fetchAllDinosaurs(filters);
      final result = _builder.build(dinosaurs);

      final layout = FractalTreeLayout(
        baseLength: dinosaurs.length > 200 ? 70 : 86,
        decay: 0.835,
        rootFanRadians: FractalTreeLayout.fullCircleFan,
        branchCurveFactor: 0.22,
        siblingAngleGap: 0.03,
      )..compute(result.root);

      _root = result.root;
      _layout = layout;
      _placedCount = result.placedCount;
      _unplacedCount = result.unplacedCount;
      _totalGenera = result.totalGenera;
      _appliedFilters = filters;
      _loaded = true;
      _error = null;

      if (kDebugMode) {
        debugPrint(
          'PhyloTreeController: fractal tree with $_totalGenera genera '
          '($_placedCount placed, $_unplacedCount unplaced)',
        );
      }
    } on DinosaurServiceException catch (error) {
      _error = error.message;
      _loaded = false;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      _loaded = false;
      if (kDebugMode) {
        debugPrint('PhyloTreeController.reload failed: $error');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<DinosaurSummary>> _fetchAllDinosaurs(
    DinosaurCatalogFilters filters,
  ) async {
    final all = <DinosaurSummary>[];
    var offset = 0;
    var hasMore = true;
    final hasSearch = filters.searchQuery.trim().isNotEmpty;

    while (hasMore) {
      final response = await _service.fetchDinosaurs(
        limit: _pageSize,
        offset: offset,
        sort: 'name',
        mode: 'inventory',
        q: hasSearch ? filters.searchQuery.trim() : null,
        maYounger:
            !hasSearch && filters.hasTimeFilter ? filters.maYounger : null,
        maOlder: !hasSearch && filters.hasTimeFilter ? filters.maOlder : null,
        diets: filters.diets,
        lengthMMin: filters.hasLengthFilter ? filters.lengthMMin : null,
        lengthMMax: filters.hasLengthFilter ? filters.lengthMMax : null,
        massKgMin: filters.hasMassFilter ? filters.massKgMin : null,
        massKgMax: filters.hasMassFilter ? filters.massKgMax : null,
      );

      all.addAll(response.items);
      offset += response.items.length;
      hasMore = response.hasMore;
      if (response.items.isEmpty) break;
    }

    return all;
  }

  static bool _filtersEqual(
    DinosaurCatalogFilters a,
    DinosaurCatalogFilters b,
  ) {
    return a.searchQuery == b.searchQuery &&
        a.maYounger == b.maYounger &&
        a.maOlder == b.maOlder &&
        a.lengthMMin == b.lengthMMin &&
        a.lengthMMax == b.lengthMMax &&
        a.massKgMin == b.massKgMin &&
        a.massKgMax == b.massKgMax &&
        setEquals(a.diets, b.diets);
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalogChanged);
    _service.dispose();
    super.dispose();
  }
}
