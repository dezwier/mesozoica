import 'package:flutter/foundation.dart';

import '../models/dinosaur.dart';
import '../services/dinosaur_service.dart';

class DinosaurCatalogController extends ChangeNotifier {
  DinosaurCatalogController({DinosaurService? service})
      : _service = service ?? DinosaurService();

  final DinosaurService _service;

  List<DinosaurSummary> _items = [];
  bool _loading = false;
  String? _error;

  List<DinosaurSummary> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  String? get error => _error;
  bool get isEmpty => !_loading && _error == null && _items.isEmpty;

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (!force && _items.isNotEmpty) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _service.fetchDinosaurs();
      _items = response.items;
      _error = null;
    } on DinosaurServiceException catch (error) {
      _error = error.message;
    } catch (error) {
      _error = 'Could not reach the API. Is the backend running?';
      if (kDebugMode) {
        debugPrint('DinosaurCatalogController.load failed: $error');
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
