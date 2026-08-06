import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:mesozoica/config/api_endpoints.dart';
import 'package:mesozoica/core/networking/api_transport.dart';
import 'package:mesozoica/config/app_config.dart';
import 'package:mesozoica/models/tool.dart';
import 'package:mesozoica/models/tool_session.dart';
import 'package:mesozoica/core/networking/api_client.dart';

class ToolService {
  ToolService({http.Client? client, ApiTransport? transport})
    : _client = client ?? http.Client(),
      _transport = transport ?? ApiClient.instance;

  final http.Client _client;
  final ApiTransport _transport;

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    return jsonBody ? const {'Content-Type': 'application/json'} : const {};
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
    final uri = ApiEndpoints.toolsUri(
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
    final response = await _transport
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
    final uri = ApiEndpoints.toolCategoriesUri(showAll: showAll, mode: mode);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await _transport
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
    final uri = ApiEndpoints.toolUri(id);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await _transport
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
    final uri = ApiEndpoints.toolImageVersionsUri();
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await _transport
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
    final uri = ApiEndpoints.toolCollectUri(id);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri version=$version');
    }
    final response = await _transport
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

  Future<void> discardTool(int toolId) async {
    final uri = ApiEndpoints.toolDiscardUri(toolId);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await _transport
        .sendPost(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 204) {
      throw ToolServiceException(
        'Failed to discard tool (${response.statusCode})',
      );
    }
  }

  Future<ToolSessionListResponse> fetchToolSessions(int toolId) async {
    final uri = ApiEndpoints.toolSessionsUri(toolId);
    if (kDebugMode) debugPrint('ToolService GET $uri');
    final response = await _transport
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
    final response = await _transport
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
    int? siteId,
  }) async {
    final uri = ApiEndpoints.toolSessionsUri(toolId);
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
    if (siteId != null) body['site_id'] = siteId;
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await _transport
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
    final uri = ApiEndpoints.activeToolSessionsUri(actionKey: actionKey);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await _transport
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
    final uri = ApiEndpoints.toolSessionUri(sessionId);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await _transport
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
    final uri = ApiEndpoints.toolSessionCancelUri(sessionId);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await _transport
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
