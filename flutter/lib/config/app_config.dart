import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Global application configuration.
class AppConfig {
  AppConfig._();

  static bool isDebugMode = kDebugMode;
  static bool isApiRunning = false;

  /// Local FastAPI dev server.
  static const String baseApiUrl = 'http://127.0.0.1:8000';

  /// Railway production URL — uncomment when deployed.
  // static const String baseApiUrl = 'https://your-service.up.railway.app';

  static Uri get healthUri => Uri.parse('$baseApiUrl/health');

  static Uri dinosaursUri({int limit = 200, int offset = 0}) => Uri.parse(
        '$baseApiUrl/api/v1/dinosaurs?limit=$limit&offset=$offset',
      );

  static Future<bool> checkApiHealth() async {
    try {
      final response = await http.get(healthUri).timeout(const Duration(seconds: 5));
      isApiRunning = response.statusCode == 200;
      if (isApiRunning && isDebugMode) {
        debugPrint('API health: ${response.body}');
      }
      return isApiRunning;
    } catch (error) {
      isApiRunning = false;
      if (isDebugMode) {
        debugPrint('API health check failed: $error');
      }
      return false;
    }
  }

  static Map<String, dynamic>? decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
