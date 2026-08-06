import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AuthTokenStore {
  Future<void> save(String token);
  Future<String?> load();
  Future<void> clear();
}

class SharedPreferencesTokenStore implements AuthTokenStore {
  static const _tokenKey = 'auth_token';

  @override
  Future<void> save(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

/// Static compatibility facade; new repositories inject [AuthTokenStore].
class TokenStorage {
  static final AuthTokenStore _store = SharedPreferencesTokenStore();

  static Future<void> saveToken(String token) => _store.save(token);

  static Future<String?> loadToken() => _store.load();

  static Future<void> clearToken() => _store.clear();
}
