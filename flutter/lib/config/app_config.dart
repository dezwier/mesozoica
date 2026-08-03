import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/catalog_data_source.dart';

import 'api_endpoints.dart';

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

  static Uri dinosaursUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    bool? llmEnriched,
    Set<String> diets = const {},
    double? lengthMMin,
    double? lengthMMax,
    double? massKgMin,
    double? massKgMax,
    String mode = 'catalog',
  }) =>
      ApiEndpoints.dinosaursUri(
        limit: limit,
        offset: offset,
        sort: sort,
        seed: seed,
        q: q,
        maYounger: maYounger,
        maOlder: maOlder,
        hasCustomImage: hasCustomImage,
        llmEnriched: llmEnriched,
        diets: diets,
        lengthMMin: lengthMMin,
        lengthMMax: lengthMMax,
        massKgMin: massKgMin,
        massKgMax: massKgMax,
        mode: mode,
      );

  static Uri dinosaurArticleUri(int id) =>
      ApiEndpoints.dinosaurArticleUri(id);

  static Uri dinosaurUri(int id) =>
      ApiEndpoints.dinosaurUri(id);

  static Uri dinosaurStatusUri(int id) =>
      ApiEndpoints.dinosaurStatusUri(id);

  static Uri dinosaurCollectUri(int id) =>
      ApiEndpoints.dinosaurCollectUri(id);

  static Uri dinosaurDiscardUri(int id) =>
      ApiEndpoints.dinosaurDiscardUri(id);

  static Uri dinosaurImageVersionsUri() =>
      ApiEndpoints.dinosaurImageVersionsUri();

  static Uri fossilsUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    String? dinoQ,
    String? fossilQ,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    bool hasCustomFossilImage = false,
    bool? llmEnriched,
    int? dinosaurId,
    CatalogDataSource dataSource = CatalogDataSource.archive,
    bool includeHidden = false,
  }) =>
      ApiEndpoints.fossilsUri(limit: limit, offset: offset, sort: sort, seed: seed, q: q, dinoQ: dinoQ, fossilQ: fossilQ, maYounger: maYounger, maOlder: maOlder, hasCustomImage: hasCustomImage, hasCustomFossilImage: hasCustomFossilImage, llmEnriched: llmEnriched, dinosaurId: dinosaurId, dataSource: dataSource, includeHidden: includeHidden);

  static Uri fossilUri(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
  }) =>
      ApiEndpoints.fossilUri(id, dataSource: dataSource);

  static Uri fossilStatusUri(int id) =>
      ApiEndpoints.fossilStatusUri(id);

  static Uri fossilDiscardUri(int id) =>
      ApiEndpoints.fossilDiscardUri(id);

  static Uri sitesUri({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    CatalogDataSource dataSource = CatalogDataSource.archive,
    int? siteIdMin,
    bool showAll = false,
    List<String>? howDiscovered,
    DateTime? discoveredAfter,
    DateTime? discoveredBefore,
    double? lat,
    double? lon,
    double? minLat,
    double? maxLat,
    double? minLon,
    double? maxLon,
    bool includeExactOdds = false,
  }) =>
      ApiEndpoints.sitesUri(limit: limit, offset: offset, sort: sort, seed: seed, q: q, maYounger: maYounger, maOlder: maOlder, hasCustomImage: hasCustomImage, dataSource: dataSource, siteIdMin: siteIdMin, showAll: showAll, howDiscovered: howDiscovered, discoveredAfter: discoveredAfter, discoveredBefore: discoveredBefore, lat: lat, lon: lon, minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, includeExactOdds: includeExactOdds);

  static Uri fieldSiteEnsureUri() =>
      ApiEndpoints.fieldSiteEnsureUri();

  static Uri fieldSiteEnsureJobUri(int jobId) =>
      ApiEndpoints.fieldSiteEnsureJobUri(jobId);

  static Uri fieldDataPurgeUri({
    bool userSites = true,
    bool userFossils = true,
    bool sites = true,
    bool fossils = true,
    bool sessionEvents = true,
    bool sessions = true,
  }) =>
      ApiEndpoints.fieldDataPurgeUri(
        userSites: userSites,
        userFossils: userFossils,
        sites: sites,
        fossils: fossils,
        sessionEvents: sessionEvents,
        sessions: sessions,
      );

  static Uri siteTypesUri({
    int limit = 200,
    int offset = 0,
  }) =>
      ApiEndpoints.siteTypesUri(limit: limit, offset: offset);

  static Uri siteUri(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
    bool includeExactOdds = false,
  }) =>
      ApiEndpoints.siteUri(
        id,
        dataSource: dataSource,
        includeExactOdds: includeExactOdds,
      );

  static Uri siteDiscoverUri(int id) =>
      ApiEndpoints.siteDiscoverUri(id);

  static Uri siteStatusUri(int id) =>
      ApiEndpoints.siteStatusUri(id);

  static Uri siteDiscardUri(int id) =>
      ApiEndpoints.siteDiscardUri(id);

  static Uri fieldSurveyJobUri(int jobId) =>
      ApiEndpoints.fieldSurveyJobUri(jobId);

  static Uri sitesNearbyDiscoverableUri({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
    bool includeExactOdds = false,
  }) =>
      ApiEndpoints.sitesNearbyDiscoverableUri(
        lat: lat,
        lon: lon,
        radiusKm: radiusKm,
        includeExactOdds: includeExactOdds,
      );

  static Uri sitesNearbyUri({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
    CatalogDataSource dataSource = CatalogDataSource.field,
    bool showAll = false,
    bool includeExactOdds = false,
  }) =>
      ApiEndpoints.sitesNearbyUri(
        lat: lat,
        lon: lon,
        radiusKm: radiusKm,
        dataSource: dataSource,
        showAll: showAll,
        includeExactOdds: includeExactOdds,
      );

  static Uri siteFossilsUri(int siteId, {bool includeHidden = false}) =>
      ApiEndpoints.siteFossilsUri(siteId, includeHidden: includeHidden);

  static Uri siteDinosaursUri(int siteId) =>
      ApiEndpoints.siteDinosaursUri(siteId);

  static Uri siteGroupsUri(int siteId) =>
      ApiEndpoints.siteGroupsUri(siteId);

  static Uri toolsUri({
    int limit = 200,
    int offset = 0,
    String sort = 'category',
    String mode = 'inventory',
    String? seed,
    String? q,
    Set<String> categories = const {},
    bool hasCustomImage = false,
    bool showAll = false,
  }) =>
      ApiEndpoints.toolsUri(limit: limit, offset: offset, sort: sort, mode: mode, seed: seed, q: q, categories: categories, hasCustomImage: hasCustomImage, showAll: showAll);

  static Uri toolCategoriesUri({
    bool showAll = false,
    String mode = 'inventory',
  }) =>
      ApiEndpoints.toolCategoriesUri(showAll: showAll, mode: mode);

  static Uri toolUri(int id) =>
      ApiEndpoints.toolUri(id);

  static Uri toolCollectUri(int id) =>
      ApiEndpoints.toolCollectUri(id);

  static Uri toolDiscardUri(int id) =>
      ApiEndpoints.toolDiscardUri(id);

  static Uri toolImageVersionsUri() =>
      ApiEndpoints.toolImageVersionsUri();

  static Uri toolSessionsUri(int toolId) =>
      ApiEndpoints.toolSessionsUri(toolId);

  static Uri activeToolSessionsUri({String? actionKey}) =>
      ApiEndpoints.activeToolSessionsUri(actionKey: actionKey);

  static Uri toolSessionUri(int sessionId) =>
      ApiEndpoints.toolSessionUri(sessionId);

  static Uri toolSessionCancelUri(int sessionId) =>
      ApiEndpoints.toolSessionCancelUri(sessionId);

  static Uri weatherUri({required double lat, required double lon}) =>
      ApiEndpoints.weatherUri(lat: lat, lon: lon);

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
