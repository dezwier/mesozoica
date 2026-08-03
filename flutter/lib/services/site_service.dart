import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/catalog_data_source.dart';
import '../models/site.dart';
import '../models/site_type.dart';
import 'api_client.dart';
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
      howDiscovered: howDiscovered,
      discoveredAfter: discoveredAfter,
      discoveredBefore: discoveredBefore,
      lat: lat,
      lon: lon,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      includeExactOdds: includeExactOdds,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final http.Response response;
    try {
      response = await ApiClient.instance
          .sendGet(uri, client: _client, headers: await _headers())
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const SiteServiceException(
        'Timed out loading sites after 15s — server may be overloaded. Try again.',
      );
    }

    if (response.statusCode != 200) {
      final detail = _errorDetail(response.body);
      throw SiteServiceException(
        detail != null && detail.isNotEmpty
            ? 'Failed to load sites (${response.statusCode}): $detail'
            : 'Failed to load sites (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid sites response');
    }
    return SiteListResponse.fromJson(decoded);
  }

  Future<SiteTypeListResponse> fetchSiteTypes({
    int limit = 200,
    int offset = 0,
  }) async {
    final uri = AppConfig.siteTypesUri(limit: limit, offset: offset);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final http.Response response;
    try {
      response = await ApiClient.instance
          .sendGet(uri, client: _client, headers: await _headers())
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const SiteServiceException(
        'Timed out loading site types after 15s — server may be overloaded. Try again.',
      );
    }

    if (response.statusCode != 200) {
      final detail = _errorDetail(response.body);
      throw SiteServiceException(
        detail != null && detail.isNotEmpty
            ? 'Failed to load site types (${response.statusCode}): $detail'
            : 'Failed to load site types (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid site types response');
    }
    return SiteTypeListResponse.fromJson(decoded);
  }

  Future<SiteSummary> fetchSiteById(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
    bool includeExactOdds = false,
  }) async {
    final uri = AppConfig.siteUri(
      id,
      dataSource: dataSource,
      includeExactOdds: includeExactOdds,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
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

  Future<FieldDiscoverResponse> discoverSite({
    required int siteId,
    required double lat,
    required double lon,
  }) async {
    final uri = AppConfig.siteDiscoverUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'lat': lat, 'lon': lon}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final detail = _errorDetail(response.body);
      final type = _errorType(response.body);
      throw SiteServiceException(
        detail ?? 'Failed to discover site (${response.statusCode})',
        type: type,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid discover response');
    }
    return FieldDiscoverResponse.fromJson(decoded);
  }

  Future<SiteSummary> setSiteStatus({
    required int siteId,
    required String status,
    double? lat,
    double? lon,
  }) async {
    final result = await setSiteStatusDetailed(
      siteId: siteId,
      status: status,
      lat: lat,
      lon: lon,
    );
    return result.site;
  }

  Future<void> discardSite(int siteId) async {
    final uri = AppConfig.siteDiscardUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 204) {
      final detail = _errorDetail(response.body);
      throw SiteServiceException(
        detail ?? 'Failed to discard site (${response.statusCode})',
      );
    }
  }

  /// Like [setSiteStatus], but returns fossil onboard metadata when discovering.
  Future<FieldDiscoverResponse> setSiteStatusDetailed({
    required int siteId,
    required String status,
    double? lat,
    double? lon,
  }) async {
    final uri = AppConfig.siteStatusUri(siteId);
    if (kDebugMode) {
      debugPrint('SiteService POST $uri status=$status');
    }
    final body = <String, dynamic>{'status': status};
    if (lat != null) body['lat'] = lat;
    if (lon != null) body['lon'] = lon;
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      final detail = _errorDetail(response.body);
      throw SiteServiceException(
        detail ?? 'Failed to set site status (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid status response');
    }
    if (decoded.containsKey('site')) {
      return FieldDiscoverResponse.fromJson(decoded);
    }
    return FieldDiscoverResponse(
      site: SiteSummary.fromJson(decoded),
      status: 'done',
      fossilsReady: true,
    );
  }

  Future<SiteNearbyResponse> fetchNearbySites({
    required double lat,
    required double lon,
    double radiusKm = 1.0,
    CatalogDataSource dataSource = CatalogDataSource.field,
    bool showAll = false,
    bool includeExactOdds = false,
  }) async {
    final uri = AppConfig.sitesNearbyUri(
      lat: lat,
      lon: lon,
      radiusKm: radiusKm,
      dataSource: dataSource,
      showAll: showAll,
      includeExactOdds: includeExactOdds,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
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
    bool includeExactOdds = false,
  }) async {
    final uri = AppConfig.sitesNearbyDiscoverableUri(
      lat: lat,
      lon: lon,
      radiusKm: radiusKm,
      includeExactOdds: includeExactOdds,
    );
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
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
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
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

  Future<FieldEnsureJobStatus> fetchFieldEnsureJobStatus(int jobId) async {
    final uri = AppConfig.fieldSiteEnsureJobUri(jobId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      throw const SiteServiceException('Field ensure job not found');
    }
    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load field ensure job (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid field ensure job response');
    }
    return FieldEnsureJobStatus.fromJson(decoded);
  }

  /// Poll until the ensure job finishes (or [timeout] elapses).
  Future<FieldEnsureJobStatus> waitForFieldEnsureJob(
    int jobId, {
    Duration timeout = const Duration(minutes: 3),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final status = await fetchFieldEnsureJobStatus(jobId);
      if (status.isTerminal) return status;
      if (DateTime.now().isAfter(deadline)) {
        throw const SiteServiceException(
          'Timed out waiting for field site scan',
        );
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Admin-only: delete selected field scopes (progress / sites / fossils).
  Future<FieldDataPurgeResult> purgeAllFieldData({
    bool userSites = true,
    bool userFossils = true,
    bool sites = true,
    bool fossils = true,
    bool sessionEvents = true,
    bool sessions = true,
    bool xp = true,
  }) async {
    final uri = AppConfig.fieldDataPurgeUri(
      userSites: userSites,
      userFossils: userFossils,
      sites: sites,
      fossils: fossils,
      sessionEvents: sessionEvents,
      sessions: sessions,
      xp: xp,
    );
    if (kDebugMode) {
      debugPrint('SiteService DELETE $uri');
    }
    final response = await ApiClient.instance
        .sendDelete(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      final detail = _errorDetail(response.body);
      throw SiteServiceException(
        detail ?? 'Failed to purge field data (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid field purge response');
    }
    return FieldDataPurgeResult.fromJson(decoded);
  }

  Future<FieldSurveyJobStatus> fetchFieldSurveyJobStatus(int jobId) async {
    final uri = AppConfig.fieldSurveyJobUri(jobId);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      throw const SiteServiceException('Field survey job not found');
    }
    if (response.statusCode != 200) {
      throw SiteServiceException(
        'Failed to load field survey job (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SiteServiceException('Invalid field survey job response');
    }
    return FieldSurveyJobStatus.fromJson(decoded);
  }

  Future<FieldSurveyJobStatus> waitForFieldSurveyJob(
    int jobId, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final status = await fetchFieldSurveyJobStatus(jobId);
      if (status.isTerminal) return status;
      if (DateTime.now().isAfter(deadline)) {
        throw const SiteServiceException(
          'Timed out waiting for site survey',
        );
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<List<SiteFossilThumb>> fetchFossilsForSite(
    int siteId, {
    bool includeHidden = false,
  }) async {
    final uri = AppConfig.siteFossilsUri(siteId, includeHidden: includeHidden);
    if (kDebugMode) {
      debugPrint('SiteService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
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
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
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
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
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

  String? _errorType(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final type = decoded['type'];
        if (type is String && type.isNotEmpty) return type;
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _client.close();
  }
}

class SiteServiceException implements Exception {
  const SiteServiceException(this.message, {this.type});

  final String message;
  final String? type;

  bool get isDiscoveryChanceMiss => type == 'DiscoveryChanceMissError';

  @override
  String toString() => message;
}
