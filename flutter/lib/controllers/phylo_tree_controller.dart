import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/dinosaur.dart';
import '../models/phylo_tree.dart';
import '../services/dinosaur_service.dart';
import '../services/phylo_tree_builder.dart';
import '../services/phylo_tree_layout.dart';

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
  PhyloTreeLayout? _layout;
  int _placedCount = 0;
  int _unplacedCount = 0;
  int _totalGenera = 0;

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  PhyloTreeNode? get root => _root;
  PhyloTreeLayout? get layout => _layout;
  int get placedCount => _placedCount;
  int get unplacedCount => _unplacedCount;
  int get totalGenera => _totalGenera;

  Future<void> loadIfNeeded() async {
    if (_loaded || _loading) return;
    await reload();
  }

  Future<void> reload() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final dinosaurs = await _fetchAllDinosaurs();
      final result = _builder.build(dinosaurs);
      final layout = PhyloTreeLayout(
        leafSpacing: dinosaurs.length > 200 ? 36 : 48,
        levelSpacing: 72,
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
          'PhyloTreeController: built tree with $_totalGenera genera '
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
    final all = <DinosaurSummary>[];
    var offset = 0;
    var hasMore = true;

    while (hasMore) {
      final response = await _service.fetchDinosaurs(
        limit: _pageSize,
        offset: offset,
        sort: 'name',
      );
      all.addAll(response.items);
      offset += response.items.length;
      hasMore = response.hasMore;
      if (response.items.isEmpty) break;
    }

    return all;
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
