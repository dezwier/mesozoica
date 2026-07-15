import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Global application configuration.
class AppConfig {
  AppConfig._();

  static bool isDebugMode = kDebugMode;
  static bool isApiRunning = false;

  /// Debug-only test account (quick fill on Profile auth screen).
  static const String debugTestEmail = 'dezwier@mesozoica.app';
  static const String debugTestUsername = 'dezwier';
  static const String debugTestPassword = 'password123';
  static const String debugTestFullName = 'Dezwier';

  static bool get showDebugTestAccount => isDebugMode;

  /// Deployed FastAPI on Railway (default for all device builds).
  static const String productionApiUrl =
      'https://mesozoica-production.up.railway.app';

  /// Explicit override, e.g. `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
  static const String _dartDefineBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Local backend during dev: `--dart-define=USE_LOCAL_API=true`
  static const bool _useLocalApi =
      bool.fromEnvironment('USE_LOCAL_API', defaultValue: false);

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

  static Uri dinosaursUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
  }) {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'sort': sort,
    };
    if (seed != null && seed.isNotEmpty) {
      params['seed'] = seed;
    }
    final trimmedQuery = q?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      params['q'] = trimmedQuery;
    }
    if (maYounger != null && maOlder != null) {
      params['ma_younger'] = '$maYounger';
      params['ma_older'] = '$maOlder';
    }
    if (hasCustomImage) {
      params['has_custom_image'] = 'true';
    }
    return Uri.parse('$baseApiUrl/api/v1/dinosaurs').replace(
      queryParameters: params,
    );
  }

  static Uri dinosaurArticleUri(int id) =>
      Uri.parse('$baseApiUrl/api/v1/dinosaurs/$id/article');

  static Uri dinosaurUri(int id) =>
      Uri.parse('$baseApiUrl/api/v1/dinosaurs/$id');

  static Uri fossilsUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    int? dinosaurId,
  }) {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'sort': sort,
    };
    if (seed != null && seed.isNotEmpty) {
      params['seed'] = seed;
    }
    final trimmedQuery = q?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      params['q'] = trimmedQuery;
    }
    if (maYounger != null && maOlder != null) {
      params['ma_younger'] = '$maYounger';
      params['ma_older'] = '$maOlder';
    }
    if (hasCustomImage) {
      params['has_custom_image'] = 'true';
    }
    if (dinosaurId != null) {
      params['dinosaur_id'] = '$dinosaurId';
    }
    return Uri.parse('$baseApiUrl/api/v1/fossils').replace(
      queryParameters: params,
    );
  }

  static Uri fossilUri(int id) =>
      Uri.parse('$baseApiUrl/api/v1/fossils/$id');

  static Uri sitesUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
  }) {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'sort': sort,
    };
    if (seed != null && seed.isNotEmpty) {
      params['seed'] = seed;
    }
    final trimmedQuery = q?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      params['q'] = trimmedQuery;
    }
    if (maYounger != null && maOlder != null) {
      params['ma_younger'] = '$maYounger';
      params['ma_older'] = '$maOlder';
    }
    if (hasCustomImage) {
      params['has_custom_image'] = 'true';
    }
    return Uri.parse('$baseApiUrl/api/v1/sites').replace(
      queryParameters: params,
    );
  }

  static Uri siteUri(int id) => Uri.parse('$baseApiUrl/api/v1/sites/$id');

  static Uri siteFossilsUri(int siteId) =>
      Uri.parse('$baseApiUrl/api/v1/sites/$siteId/fossils');

  static Uri siteDinosaursUri(int siteId) =>
      Uri.parse('$baseApiUrl/api/v1/sites/$siteId/dinosaurs');

  static Uri siteGroupsUri(int siteId) =>
      Uri.parse('$baseApiUrl/api/v1/sites/$siteId/groups');

  static Future<bool> checkApiHealth() async {
    try {
      final response = await http.get(healthUri).timeout(const Duration(seconds: 15));
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
