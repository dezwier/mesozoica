import 'package:flutter/foundation.dart';

/// Tracks whether the initial shell/page is ready to be shown.
/// Startup data can continue loading in the background after this turns true.
class SplashHoldController extends ChangeNotifier {
  bool _isInitialPageReady = false;

  bool get isInitialPageReady => _isInitialPageReady;

  void setInitialPageReady(bool value) {
    if (_isInitialPageReady == value) return;
    _isInitialPageReady = value;
    notifyListeners();
  }

  /// Call when the next cold-style startup should show splash again.
  void reset() {
    if (!_isInitialPageReady) return;
    _isInitialPageReady = false;
    notifyListeners();
  }
}
