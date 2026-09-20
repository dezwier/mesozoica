import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Global application configuration.
class AppConfig {
  AppConfig._();

  static bool isDebugMode = kDebugMode;
  static bool isApiRunning = false;

  /// Sign in with Apple requires a paid Apple Developer Program team in Xcode.
  static const bool enableAppleSignIn = bool.fromEnvironment(
    'ENABLE_APPLE_SIGN_IN',
    defaultValue: true,
  );

  /// Deployed FastAPI on Railway (default for all device builds).
  static const String productionApiUrl =
      'https://mesozoica-production.up.railway.app';

  /// Explicit override, e.g. `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
  static const String _dartDefineBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Local backend during dev: `--dart-define=USE_LOCAL_API=true`
  static const bool _useLocalApi = bool.fromEnvironment(
    'USE_LOCAL_API',
    defaultValue: false,
  );

  static String get baseApiUrl {
    if (_dartDefineBaseUrl.isNotEmpty) {
      return _dartDefineBaseUrl;
    }
    if (_useLocalApi) {
      return _localDevApiUrl;
    }
    return productionApiUrl;
  }

  static String get _localDevApiUrl {
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static Uri get healthUri => Uri.parse('$baseApiUrl/health');

  static Future<bool> checkApiHealth() async {
    try {
      final response = await http
          .get(healthUri)
          .timeout(const Duration(seconds: 15));
      isApiRunning = response.statusCode == 200;
      if (isApiRunning && isDebugMode) {
        debugPrint('API health ($baseApiUrl): ${response.body}');
      }
      return isApiRunning;
    } catch (error) {
      isApiRunning = false;
      if (isDebugMode) {
        debugPrint('API health check failed ($baseApiUrl): $error');
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
