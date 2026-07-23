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

  Future<AerialReconMission> startAerialRecon({
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
    return AerialReconMission.fromJson(decoded);
  }

  Future<List<AerialReconMission>> fetchAerialReconMissions() async {
    final uri = AppConfig.aerialReconMissionsUri();
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load aerial recon missions (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid aerial recon missions response');
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const ToolServiceException('Invalid aerial recon missions response');
    }
    return [
      for (final item in items)
        if (item is Map<String, dynamic>) AerialReconMission.fromJson(item),
    ];
  }

  Future<AerialReconMission> cancelAerialRecon(int missionId) async {
    final uri = AppConfig.aerialReconCancelUri(missionId);
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
        _errorDetail(response.body) ??
            'Failed to cancel Aerial Recon (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid aerial recon cancel response');
    }
    return AerialReconMission.fromJson(decoded);
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

class AerialReconMission {
  const AerialReconMission({
    required this.missionId,
    required this.status,
    required this.route,
    required this.routeLengthKm,
    required this.flightDurationS,
    required this.createdAt,
    required this.toolId,
    this.flightStartedAt,
    this.flightEndsAt,
    this.toolImageUrl,
  });

  final int missionId;
  final String status;
  final List<LatLng> route;
  final double routeLengthKm;
  final int flightDurationS;
  final DateTime? flightStartedAt;
  final DateTime? flightEndsAt;
  final DateTime createdAt;
  final int toolId;
  final String? toolImageUrl;

  bool get isActive => status == 'ensuring' || status == 'flying';
  bool get isFlying => status == 'flying';
  bool get isEnsuring => status == 'ensuring';
  bool get isPast =>
      status == 'done' || status == 'failed' || status == 'cancelled';

  factory AerialReconMission.fromJson(Map<String, dynamic> json) {
    final rawRoute = json['route'];
    final route = <LatLng>[];
    if (rawRoute is List) {
      for (final item in rawRoute) {
        if (item is! Map) continue;
        final lat = item['lat'];
        final lon = item['lon'];
        if (lat is num && lon is num) {
          route.add(LatLng(lat.toDouble(), lon.toDouble()));
        }
      }
    }
    return AerialReconMission(
      missionId: json['mission_id'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      route: route,
      routeLengthKm: (json['route_length_km'] as num?)?.toDouble() ?? 0,
      flightDurationS: json['flight_duration_s'] as int? ?? 0,
      flightStartedAt: _parseDate(json['flight_started_at']),
      flightEndsAt: _parseDate(json['flight_ends_at']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now().toUtc(),
      toolId: json['tool_id'] as int? ?? 0,
      toolImageUrl: json['tool_image_url'] as String?,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

/// Progress along the route in 0..1 using the same arc-fraction timing as
/// backend discovery scheduling.
double aerialReconProgressFraction(
  AerialReconMission mission, {
  DateTime? now,
}) {
  if (mission.isEnsuring || mission.flightStartedAt == null) return 0;
  final started = mission.flightStartedAt!;
  final duration = mission.flightDurationS;
  if (duration <= 0) return mission.isPast ? 1 : 0;
  final clock = now ?? DateTime.now().toUtc();
  final elapsed = clock.difference(started).inMilliseconds / 1000.0;
  return (elapsed / duration).clamp(0.0, 1.0);
}

class ToolServiceException implements Exception {
  const ToolServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
