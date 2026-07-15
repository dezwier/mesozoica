import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;

  Profile? _currentUser;
  bool _isLoading = false;
  bool _isInitializing = true;

  Profile? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;

  AuthService get authService => _authService;

  Future<void> initialize() async {
    try {
      _currentUser = await _authService.loadStoredUser();
      if (_currentUser != null) {
        _currentUser = await _authService.refreshProfile();
      }
    } catch (_) {
      _currentUser = null;
      await _authService.clearStoredAuth();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    _setLoading(true);
    final result = await _authService.login(email, password);
    if (result['success'] == true) {
      _currentUser = result['user'] as Profile;
      notifyListeners();
    }
    _setLoading(false);
    return result;
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? fullName,
  }) async {
    _setLoading(true);
    final result = await _authService.register(
      username: username,
      email: email,
      password: password,
      fullName: fullName,
    );
    if (result['success'] == true) {
      _currentUser = result['user'] as Profile;
      notifyListeners();
    }
    _setLoading(false);
    return result;
  }

  Future<Map<String, dynamic>> exchangeFirebaseToken(String idToken) async {
    _setLoading(true);
    final result = await _authService.exchangeFirebaseToken(idToken);
    if (result['success'] == true) {
      _currentUser = result['user'] as Profile;
      notifyListeners();
    }
    _setLoading(false);
    return result;
  }

  Future<void> refreshProfile() async {
    if (_currentUser == null) return;
    _currentUser = await _authService.refreshProfile();
    notifyListeners();
  }

  Future<void> applyUser(Profile user) async {
    _currentUser = user;
    notifyListeners();
  }

  Future<void> logout() async {
    await _authService.clearStoredAuth();
    _currentUser = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
