import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/tool.dart';
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
  }) async {
    final uri = AppConfig.toolCategoriesUri(showAll: showAll);
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

  Future<ToolSummary> collectTool(int id) async {
    final uri = AppConfig.toolCollectUri(id);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
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

  Future<AerialReconMissionResult> startAerialRecon({
    required int toolId,
    required List<LatLng> route,
    required LatLng origin,
  }) async {
    final uri = AppConfig.toolAerialReconUri(toolId);
    final body = jsonEncode({
      'route': [
        for (final point in route) {'lat': point.latitude, 'lon': point.longitude},
      ],
      'origin_lat': origin.latitude,
      'origin_lon': origin.longitude,
    });
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 202) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to deploy Aerial Recon (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid aerial recon response');
    }
    return AerialReconMissionResult.fromJson(decoded);
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

class AerialReconMissionResult {
  const AerialReconMissionResult({
    required this.missionId,
    required this.status,
    required this.routeLengthKm,
    required this.flightDurationS,
  });

  final int missionId;
  final String status;
  final double routeLengthKm;
  final int flightDurationS;

  factory AerialReconMissionResult.fromJson(Map<String, dynamic> json) {
    return AerialReconMissionResult(
      missionId: json['mission_id'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      routeLengthKm: (json['route_length_km'] as num?)?.toDouble() ?? 0,
      flightDurationS: json['flight_duration_s'] as int? ?? 0,
    );
  }
}

class ToolServiceException implements Exception {
  const ToolServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
