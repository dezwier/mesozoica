import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/tool.dart';
import '../models/tool_session.dart';
import 'api_client.dart';
import 'token_storage.dart';

class ToolService {
  ToolService({http.Client? client}) : _client = client ?? http.Client();

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

  Future<ToolListResponse> fetchTools({
    int limit = 200,
    int offset = 0,
    String sort = 'category',
    String mode = 'inventory',
    String? seed,
    String? q,
    Set<String> categories = const {},
    bool hasCustomImage = false,
    bool showAll = false,
  }) async {
    final uri = AppConfig.toolsUri(
      limit: limit,
      offset: offset,
      sort: sort,
      mode: mode,
      seed: seed,
      q: q,
      categories: categories,
      hasCustomImage: hasCustomImage,
      showAll: showAll,
    );
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load tools (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tools response');
    }
    return ToolListResponse.fromJson(decoded);
  }

  Future<List<ToolCategoryOption>> fetchCategories({
    bool showAll = false,
    String mode = 'inventory',
  }) async {
    final uri = AppConfig.toolCategoriesUri(showAll: showAll, mode: mode);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load tool categories (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tool categories response');
    }
    final rawItems = decoded['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map<String, dynamic>>()
        .map(ToolCategoryOption.fromJson)
        .where((item) => item.value.isNotEmpty)
        .toList(growable: false);
  }

  Future<ToolSummary> fetchToolById(int id) async {
    final uri = AppConfig.toolUri(id);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw ToolServiceException('Tool not found');
    }
    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load tool (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tool response');
    }
    return ToolSummary.fromJson(decoded);
  }

  Future<List<String>> listToolImageVersions() async {
    final uri = AppConfig.toolImageVersionsUri();
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load tool image versions (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tool image versions response');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const ToolServiceException('Invalid tool image versions items');
    }
    final names = <String>[];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final name = item['name'];
        if (name is String && name.trim().isNotEmpty) {
          names.add(name.trim());
        }
      }
    }
    return names;
  }

  Future<ToolSummary> collectTool(int id, {required String version}) async {
    final uri = AppConfig.toolCollectUri(id);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri version=$version');
    }
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'version': version}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to collect tool (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid collect response');
    }
    return ToolSummary.fromJson(decoded);
  }

  Future<ToolSessionListResponse> fetchToolSessions(int toolId) async {
    final uri = AppConfig.toolSessionsUri(toolId);
    if (kDebugMode) debugPrint('ToolService GET $uri');
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load tool sessions (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tool sessions response');
    }
    return ToolSessionListResponse.fromJson(decoded);
  }

  Future<ToolSummary> updateToolParams(
    int toolId,
    Map<String, dynamic> params,
  ) async {
    final uri = Uri.parse(
      '${AppConfig.baseApiUrl}/api/v1/tools/$toolId/params',
    );
    if (kDebugMode) debugPrint('ToolService PATCH $uri');
    final response = await ApiClient.instance
        .sendPatch(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'params': params}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to update tool params (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid update params response');
    }
    return ToolSummary.fromJson(decoded);
  }

  Future<ToolSession> startToolSession({
    required int toolId,
    List<LatLng>? route,
    LatLng? origin,
    double? lat,
    double? lon,
  }) async {
    final uri = AppConfig.toolSessionsUri(toolId);
    final body = <String, dynamic>{};
    if (route != null) {
      body['route'] = [
        for (final point in route)
          {'lat': point.latitude, 'lon': point.longitude},
      ];
    }
    if (origin != null) {
      body['origin_lat'] = origin.latitude;
      body['origin_lon'] = origin.longitude;
    }
    if (lat != null) body['lat'] = lat;
    if (lon != null) body['lon'] = lon;
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 201 && response.statusCode != 202) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to start tool session (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tool session response');
    }
    return ToolSession.fromJson(decoded);
  }

  Future<List<ToolSession>> fetchActiveSessions({String? actionKey}) async {
    final uri = AppConfig.activeToolSessionsUri(actionKey: actionKey);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load active sessions (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid active sessions response');
    }
    return ToolSessionListResponse.fromJson(decoded).items;
  }

  Future<ToolSession?> fetchActiveSession({required String actionKey}) async {
    final items = await fetchActiveSessions(actionKey: actionKey);
    for (final item in items) {
      if (item.isActive && !item.isExpired) return item;
    }
    return null;
  }

  Future<ToolSession> fetchSession(int sessionId) async {
    final uri = AppConfig.toolSessionUri(sessionId);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to load session (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tool session response');
    }
    return ToolSession.fromJson(decoded);
  }

  Future<ToolSession> cancelSession(int sessionId) async {
    final uri = AppConfig.toolSessionCancelUri(sessionId);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(uri, client: _client, headers: await _headers(jsonBody: true))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to cancel session (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid session cancel response');
    }
    return ToolSession.fromJson(decoded);
  }

  static String? _errorDetail(String body) {
    final decoded = AppConfig.decodeJson(body);
    if (decoded == null) return null;
    final detail = decoded['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    return null;
  }

  void dispose() {
    _client.close();
  }
}

class ToolServiceException implements Exception {
  const ToolServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
