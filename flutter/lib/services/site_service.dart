import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../controllers/catalog_mode_controller.dart';
import '../models/site.dart';
import 'token_storage.dart';

class SiteService {
  SiteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final headers = <String, String>{};
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    try {
      final token = await TokenStorage.loadToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // SharedPreferences unavailable in some unit-test environments.
    }
    return headers;
  }

  Future<SiteListResponse> fetchSites({
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
  }) async {
    final uri = AppConfig.sitesUri(
      limit: limit,
      offset: offset,
      sort: sort,
      seed: seed,
      q: q,
      maYounger: maYounger,
      maOlder: maOlder,
      hasCustomImage: hasCustomImage,
      dataSource: dataSource,
      siteIdMin: siteIdMin,
      showAll: showAll,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load sites (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid sites response');
    }
    return SiteListResponse.fromJson(decoded);
  }

  Future<SiteSummary> fetchSiteById(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
  }) async {
    final uri = AppConfig.siteUri(id, dataSource: dataSource);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw SiteServiceException('Site not found');
    }
    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site response');
    }
    return SiteSummary.fromJson(decoded);
  }

  Future<SiteSummary> discoverSite({
    required int siteId,
    required double lat,
    required double lon,
  }) async {
    final uri = AppConfig.siteDiscoverUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService POST $uri');
    }
    final response = await _client
        .post(
          uri,
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'lat': lat, 'lon': lon}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final detail = _errorDetail(response.body);
      throw SiteServiceException(
        detail ?? 'Failed to discover site (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid discover response');
    }
    return SiteSummary.fromJson(decoded);
  }

  Future<SiteNearbyResponse> fetchNearbySites({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
    CatalogDataSource dataSource = CatalogDataSource.field,
    bool showAll = false,
  }) async {
    final uri = AppConfig.sitesNearbyUri(
      lat: lat,
      lon: lon,
      radiusKm: radiusKm,
      dataSource: dataSource,
      showAll: showAll,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load nearby sites (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid nearby sites response');
    }
    return SiteNearbyResponse.fromJson(decoded);
  }

  Future<SiteNearbyResponse> fetchNearbyDiscoverableSites({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
  }) async {
    final uri = AppConfig.sitesNearbyDiscoverableUri(
      lat: lat,
      lon: lon,
      radiusKm: radiusKm,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load discoverable sites (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid discoverable sites response');
    }
    return SiteNearbyResponse.fromJson(decoded);
  }

  Future<FieldEnsureResponse> requestFieldSiteEnsure({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
    String? reason,
  }) async {
    final uri = AppConfig.fieldSiteEnsureUri();
    if (kDebugMode) {
      debugPrint('SiteService POST $uri reason=${reason ?? '-'}');
    }
    final body = <String, dynamic>{
      'lat': lat,
      'lon': lon,
      'radius_km': radiusKm,
    };
    if (reason != null && reason.isNotEmpty) {
      body['reason'] = reason;
    }
    final response = await _client
        .post(
          uri,
          headers: await _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 3));

    if (response.statusCode != 202) {
      throw SiteServiceException(
        'Failed to schedule field site ensure (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid field ensure response');
    }
    return FieldEnsureResponse.fromJson(decoded);
  }

  Future<List<SiteFossilThumb>> fetchFossilsForSite(int siteId) async {
    final uri = AppConfig.siteFossilsUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site fossils (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site fossils response');
    }
    return SiteFossilThumbListResponse.fromJson(decoded).items;
  }

  Future<List<SiteDinosaurThumb>> fetchDinosaursForSite(int siteId) async {
    final uri = AppConfig.siteDinosaursUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site dinosaurs (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site dinosaurs response');
    }
    return SiteDinosaurThumbListResponse.fromJson(decoded).items;
  }

  Future<List<SiteDinoFossilGroup>> fetchDinoFossilGroupsForSite(
    int siteId,
  ) async {
    final uri = AppConfig.siteGroupsUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await _client
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load site groups (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site groups response');
    }
    return SiteDinoFossilGroupListResponse.fromJson(decoded).items;
  }

  String? _errorDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map) {
          return detail['message'] as String? ?? detail.toString();
        }
        if (detail is String) return detail;
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _client.close();
  }
}

class SiteServiceException implements Exception {
  const SiteServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
