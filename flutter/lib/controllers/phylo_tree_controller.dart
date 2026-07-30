import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../controllers/dinosaur_catalog_controller.dart';
import '../models/dinosaur.dart';
import '../models/phylo_tree.dart';
import '../services/dinosaur_service.dart';
import '../utils/curated_image_url.dart';
import '../widgets/tree/fractal_tree_layout.dart';
import '../utils/phylo_tree_builder.dart';

class PhyloTreeController extends ChangeNotifier {
  PhyloTreeController({
    DinosaurService? service,
    PhyloTreeBuilder? builder,
  })  : _service = service ?? DinosaurService(),
        _builder = builder ?? const PhyloTreeBuilder();

  static const _pageSize = 500;

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
  DinosaurCatalogFilters _filters = DinosaurCatalogFilters.defaults;
  bool _useClientCustomImageFilter = false;

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  PhyloTreeNode? get root => _root;
  FractalTreeLayout? get layout => _layout;
  int get placedCount => _placedCount;
  int get unplacedCount => _unplacedCount;
  int get totalGenera => _totalGenera;
  DinosaurCatalogFilters get filters => _filters;
  bool get hasActiveFilters => _filters.hasActiveFilters;

  Future<void> loadIfNeeded() async {
    if (_loaded || _loading) return;
    await reload();
  }

  Future<void> applyFilters(DinosaurCatalogFilters filters) async {
    _filters = filters;
    await reload();
  }

  Future<void> reload() async {
    _loading = true;
    _error = null;
    _useClientCustomImageFilter = false;
    notifyListeners();

    try {
      final dinosaurs = await _fetchAllDinosaurs();
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

  Future<List<DinosaurSummary>> _fetchAllDinosaurs() async {
    if (_filters.onlyCustomImage && _useClientCustomImageFilter) {
      return _fetchAllCuratedClientSide();
    }

    final all = <DinosaurSummary>[];
    var offset = 0;
    var hasMore = true;
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;

    while (hasMore) {
      final response = await _service.fetchDinosaurs(
        limit: _pageSize,
        offset: offset,
        sort: 'name',
        q: hasSearch ? _filters.searchQuery.trim() : null,
        maYounger:
            !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
        maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
        hasCustomImage: _filters.onlyCustomImage,
        llmEnriched: _filters.onlyLlmEnriched,
      );

      if (_filters.onlyCustomImage &&
          offset == 0 &&
          !_serverHonorsCustomImageFilter(response)) {
        _useClientCustomImageFilter = true;
        if (kDebugMode) {
          debugPrint(
            'PhyloTreeController: API ignored has_custom_image; '
            'scanning catalog client-side',
          );
        }
        return _fetchAllCuratedClientSide();
      }

      all.addAll(response.items);
      offset += response.items.length;
      hasMore = response.hasMore;
      if (response.items.isEmpty) break;
    }

    return all;
  }

  bool _serverHonorsCustomImageFilter(DinosaurListResponse response) {
    return !response.items.any(
      (dinosaur) =>
          !isCuratedDinosaurImageUrl(dinosaur.mainImageUrl),
    );
  }

  Future<List<DinosaurSummary>> _fetchAllCuratedClientSide() async {
    final hasSearch = _filters.searchQuery.trim().isNotEmpty;
    final curated = <DinosaurSummary>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _service.fetchDinosaurs(
        limit: _pageSize,
        offset: offset,
        sort: 'name',
        q: hasSearch ? _filters.searchQuery.trim() : null,
        maYounger:
            !hasSearch && _filters.hasTimeFilter ? _filters.maYounger : null,
        maOlder: !hasSearch && _filters.hasTimeFilter ? _filters.maOlder : null,
        llmEnriched: _filters.onlyLlmEnriched,
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

    return curated;
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
