import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';

class AuthController extends ChangeNotifier {
  AuthController({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;

  Profile? _currentUser;
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _adminModeEnabled = false;

  Profile? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get adminModeEnabled => _adminModeEnabled;
  bool get showAdminUi => isAdmin && _adminModeEnabled;

  void setAdminModeEnabled(bool value) {
    if (_adminModeEnabled == value) return;
    _adminModeEnabled = value;
    notifyListeners();
  }

  void toggleAdminMode() => setAdminModeEnabled(!_adminModeEnabled);

  void _resetAdminMode() {
    _adminModeEnabled = false;
  }

  Future<void> initialize() async {
    try {
      _currentUser = await _authService.loadStoredUser();
      if (_currentUser != null) {
        try {
          _currentUser = await _authService.refreshProfile();
        } catch (_) {
          // Keep the cached profile (including isAdmin) when /users/me fails
          // due to transient API / DB pool errors — do not log the user out.
        }
        await PushNotificationService.registerTokenIfLoggedIn();
      }
    } catch (_) {
      _currentUser = null;
      _resetAdminMode();
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
      await PushNotificationService.registerTokenIfLoggedIn();
      await refreshProfile();
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
      await PushNotificationService.registerTokenIfLoggedIn();
      await refreshProfile();
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
      await PushNotificationService.registerTokenIfLoggedIn();
      await refreshProfile();
    }
    _setLoading(false);
    return result;
  }

  Future<void> refreshProfile() async {
    if (_currentUser == null) return;
    try {
      _currentUser = await _authService.refreshProfile();
      if (!isAdmin) _resetAdminMode();
      notifyListeners();
    } catch (_) {
      // Leave the existing profile in place on transient failures.
    }
  }

  Future<void> applyUser(Profile user) async {
    _currentUser = user;
    if (!isAdmin) _resetAdminMode();
    notifyListeners();
  }

  Future<Profile> setSkillXp({
    required String skillId,
    required int xp,
  }) async {
    final user = await _authService.setSkillXp(skillId: skillId, xp: xp);
    await applyUser(user);
    return user;
  }

  Future<void> logout() async {
    await _authService.clearStoredAuth();
    _currentUser = null;
    _resetAdminMode();
    notifyListeners();
  }

  Future<Map<String, dynamic>> sendPasswordResetEmail(String email) =>
      _authService.sendPasswordResetEmail(email);

  Future<List<String>> getLinkedAccounts() => _authService.getLinkedAccounts();

  Future<Map<String, dynamic>> checkUsername(String username) =>
      _authService.checkUsername(username);

  Future<Map<String, dynamic>> uploadProfileImage(List<int> bytes) =>
      _authService.uploadProfileImage(bytes);

  Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? email,
    String? fullName,
    String? currentPassword,
    String? password,
  }) =>
      _authService.updateProfile(
        username: username,
        email: email,
        fullName: fullName,
        currentPassword: currentPassword,
        password: password,
      );

  Future<Map<String, dynamic>> linkGoogle({
    required String idToken,
    String? accessToken,
  }) =>
      _authService.linkGoogle(idToken: idToken, accessToken: accessToken);

  Future<Map<String, dynamic>> linkApple({
    required String idToken,
    required String rawNonce,
    String? authorizationCode,
  }) =>
      _authService.linkApple(
        idToken: idToken,
        rawNonce: rawNonce,
        authorizationCode: authorizationCode,
      );

  Future<Map<String, dynamic>> unlinkProvider(String provider) =>
      _authService.unlinkProvider(provider);

  Future<Map<String, dynamic>> deleteData({
    required bool sites,
    required bool fossils,
    required bool dinosaurs,
  }) =>
      _authService.deleteData(
        sites: sites,
        fossils: fossils,
        dinosaurs: dinosaurs,
      );

  Future<Map<String, dynamic>> deleteAccount() => _authService.deleteAccount();

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
