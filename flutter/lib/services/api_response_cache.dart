import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyPrefix = 'api_cache_';
const Duration _defaultTtl = Duration(hours: 24);

/// Persistent cache for API responses (cold start / stale-while-revalidate).
class ApiResponseCache {
  ApiResponseCache._();
  static final ApiResponseCache instance = ApiResponseCache._();

  String _key(String name, int? userId) => '$_keyPrefix${name}_${userId ?? 0}';

  Future<String?> get(
    String name,
    int? userId, {
    Duration ttl = _defaultTtl,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(name, userId));
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>?;
      if (map == null) return null;
      final data = map['data'];
      final ts = map['ts'];
      if (data == null || ts == null) return null;
      final storedAt = DateTime.tryParse(ts as String);
      if (storedAt == null || DateTime.now().difference(storedAt) > ttl) {
        return null;
      }
      return data is String ? data : jsonEncode(data);
    } catch (error, stackTrace) {
      debugPrint('ApiResponseCache.get failed for $name: $error\n$stackTrace');
      return null;
    }
  }

  Future<void> set(String name, int? userId, Object payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataJson = payload is String ? payload : jsonEncode(payload);
      final entry = {
        'data': dataJson,
        'ts': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_key(name, userId), jsonEncode(entry));
    } catch (error, stackTrace) {
      debugPrint('ApiResponseCache.set failed for $name: $error\n$stackTrace');
    }
  }

  Future<void> clearForUser(int? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = userId ?? 0;
      for (final key in prefs.getKeys()) {
        if (key.startsWith(_keyPrefix) && key.endsWith('_$id')) {
          await prefs.remove(key);
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'ApiResponseCache.clearForUser failed for user=$userId: $error\n$stackTrace',
      );
    }
  }
}
