import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../utils/xp_source_labels.dart';
import 'xp_award_controller.dart';

class AuthController extends ChangeNotifier {
  AuthController({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;

  Profile? _currentUser;
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _adminModeEnabled = false;
  XpAwardController? _xpAwards;

  Profile? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get adminModeEnabled => _adminModeEnabled;
  bool get showAdminUi => isAdmin && _adminModeEnabled;

  /// Wire the global XP badge queue (from [AppShell]).
  void bindXpAwards(XpAwardController controller) {
    _xpAwards = controller;
  }

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

  /// Reload profile from the server.
  ///
  /// Pass [announceXp] true after actions known to award skill XP so the
  /// global badge can show positive XP-source deltas. Login / pull-to-refresh /
  /// purge paths leave it false.
  Future<void> refreshProfile({bool announceXp = false}) async {
    if (_currentUser == null) return;
    try {
      final next = await _authService.refreshProfile();
      await applyUser(next, announceXp: announceXp);
    } catch (_) {
      // Leave the existing profile in place on transient failures.
    }
  }

  /// Replace the local profile.
  ///
  /// When [announceXp] is true, positive per-source XP deltas are enqueued on
  /// the bound [XpAwardController] for the global earned badge.
  Future<void> applyUser(Profile user, {bool announceXp = true}) async {
    if (announceXp) {
      final awards = _diffXpAwards(_currentUser, user);
      _xpAwards?.enqueueAll(awards);
    }
    _currentUser = user;
    if (!isAdmin) _resetAdminMode();
    notifyListeners();
  }

  Future<Profile> setSkillXp({
    required String skillId,
    required int xp,
  }) async {
    final user = await _authService.setSkillXp(skillId: skillId, xp: xp);
    // Absolute admin set — not an "earned" award.
    await applyUser(user, announceXp: false);
    return user;
  }

  Future<void> logout() async {
    await _authService.clearStoredAuth();
    _currentUser = null;
    _xpAwards?.clear();
    _resetAdminMode();
    notifyListeners();
  }

  /// Emit one badge per skill_breakdown source increase; fall back to skill
  /// total when breakdown does not explain the XP delta.
  @visibleForTesting
  static List<XpAward> debugDiffXpAwards(Profile? before, Profile after) =>
      _diffXpAwards(before, after);

  static List<XpAward> _diffXpAwards(Profile? before, Profile after) {
    if (before == null) return const [];
    final prevById = <String, SkillState>{
      for (final skill in before.skills) skill.id: skill,
    };
    final awards = <XpAward>[];
    for (final skill in after.skills) {
      final prevXp = prevById[skill.id]?.xp ?? 0;
      final skillDelta = skill.xp - prevXp;
      if (skillDelta <= 0) continue;

      final prevBreakdown = before.skillBreakdown[skill.id] ?? const {};
      final nextBreakdown = after.skillBreakdown[skill.id] ?? const {};
      var accounted = 0;
      for (final entry in nextBreakdown.entries) {
        final prev = prevBreakdown[entry.key] ?? 0;
        final delta = entry.value - prev;
        if (delta <= 0) continue;
        accounted += delta;
        awards.add(
          XpAward(
            id: 0,
            skillId: skill.id,
            skillName: skill.name,
            sourceLabel: xpSourceLabel(entry.key),
            amount: delta,
          ),
        );
      }
      final remainder = skillDelta - accounted;
      if (remainder > 0) {
        awards.add(
          XpAward(
            id: 0,
            skillId: skill.id,
            skillName: skill.name,
            sourceLabel: skill.name,
            amount: remainder,
          ),
        );
      }
    }
    return awards;
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
    required bool xp,
  }) =>
      _authService.deleteData(
        sites: sites,
        fossils: fossils,
        dinosaurs: dinosaurs,
        xp: xp,
      );

  Future<Map<String, dynamic>> deleteAccount() => _authService.deleteAccount();

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
