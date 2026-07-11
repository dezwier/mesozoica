import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/dinosaur.dart';
import '../services/dinosaur_service.dart';

class DinosaurCatalogController extends ChangeNotifier {
  DinosaurCatalogController({DinosaurService? service})
      : _service = service ?? DinosaurService();

  static const pageSize = 20;

  final DinosaurService _service;
  final Random _random = Random();

  List<DinosaurSummary> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String? _seed;
  int _offset = 0;
  bool _hasMore = false;

  List<DinosaurSummary> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (!force && _items.isNotEmpty) return;

    _loading = true;
    _error = null;
    _seed = _newSeed();
    _offset = 0;
    _hasMore = false;
    _items = [];
    notifyListeners();

    try {
      final response = await _fetchPage(offset: 0);
      _items = response.items;
      _offset = response.items.length;
      _hasMore = response.hasMore;
      _error = null;
    } on DinosaurServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('DinosaurCatalogController.load failed: $error');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _seed == null) return;

    _loadingMore = true;
    notifyListeners();

    try {
      final response = await _fetchPage(offset: _offset);
      _items = [..._items, ...response.items];
      _offset += response.items.length;
      _hasMore = response.hasMore;
      _error = null;
    } on DinosaurServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error =
          'Could not reach the API at ${AppConfig.baseApiUrl}. '
          'Check your connection or try again later.';
      if (kDebugMode) {
        debugPrint('DinosaurCatalogController.loadMore failed: $error');
      }
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load(force: true);

  Future<DinosaurListResponse> _fetchPage({required int offset}) {
    return _service.fetchDinosaurs(
      limit: pageSize,
      offset: offset,
      sort: 'random',
      seed: _seed,
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
