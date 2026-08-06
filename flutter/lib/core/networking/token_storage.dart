import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AuthTokenStore {
  Future<void> save(String token);
  Future<String?> load();
  Future<void> clear();
}

class SharedPreferencesTokenStore implements AuthTokenStore {
  static const _tokenKey = 'auth_token';
  static String? _cachedToken;
  static bool _cacheInitialized = false;

  static String? get cachedToken => _cachedToken;

  @override
  Future<void> save(String token) async {
    _cachedToken = token;
    _cacheInitialized = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  @override
  Future<String?> load() async {
    if (_cacheInitialized) return _cachedToken;
    return reload();
  }

  Future<String?> reload() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    _cacheInitialized = true;
    return _cachedToken;
  }

  @override
  Future<void> clear() async {
    _cachedToken = null;
    _cacheInitialized = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

/// Static compatibility facade; new repositories inject [AuthTokenStore].
class TokenStorage {
  static final SharedPreferencesTokenStore _store =
      SharedPreferencesTokenStore();

  /// Non-blocking token access for the shared HTTP transport.
  static String? get cachedToken => SharedPreferencesTokenStore.cachedToken;

  static Future<void> saveToken(String token) => _store.save(token);

  static Future<String?> loadToken() => _store.load();

  /// Re-read persistence explicitly (used during startup and in tests).
  static Future<String?> reloadToken() => _store.reload();

  static Future<void> clearToken() => _store.clear();
}
