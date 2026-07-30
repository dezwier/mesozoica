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

  Future<AerialMission> startAerialMission({
    required int toolId,
    required List<LatLng> route,
    required LatLng origin,
  }) async {
    final uri = AppConfig.toolAerialMissionUri(toolId);
    final body = jsonEncode({
      'route': [
        for (final point in route)
          {'lat': point.latitude, 'lon': point.longitude},
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
    return AerialMission.fromJson(decoded);
  }

  Future<List<AerialMission>> fetchAerialMissions() async {
    final uri = AppConfig.aerialMissionsUri();
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
      throw const ToolServiceException(
        'Invalid aerial recon missions response',
      );
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const ToolServiceException(
        'Invalid aerial recon missions response',
      );
    }
    return [
      for (final item in items)
        if (item is Map<String, dynamic>) AerialMission.fromJson(item),
    ];
  }

  Future<AerialMission> cancelAerialMission(int missionId) async {
    final uri = AppConfig.aerialMissionCancelUri(missionId);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(uri, client: _client, headers: await _headers(jsonBody: true))
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
    return AerialMission.fromJson(decoded);
  }

  Future<GuidanceSession> startGuidanceSession({required int toolId}) async {
    final uri = AppConfig.toolGuidanceSessionUri(toolId);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(uri, client: _client, headers: await _headers(jsonBody: true))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to start guidance session (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid guidance session response');
    }
    return GuidanceSession.fromJson(decoded);
  }

  Future<GuidanceSession?> fetchActiveGuidanceSession() async {
    final uri = AppConfig.activeGuidanceSessionUri();
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load guidance session (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid guidance session response');
    }
    return GuidanceSession.fromJson(decoded);
  }

  Future<GuidanceSession> cancelGuidanceSession() async {
    final uri = AppConfig.cancelGuidanceSessionUri();
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(uri, client: _client, headers: await _headers(jsonBody: true))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to cancel guidance session (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid guidance cancel response');
    }
    return GuidanceSession.fromJson(decoded);
  }

  Future<FormationMapSession> startFormationMapSession({
    required int toolId,
  }) async {
    final uri = AppConfig.toolFormationMapSessionUri(toolId);
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(uri, client: _client, headers: await _headers(jsonBody: true))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to start formation map session (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException(
        'Invalid formation map session response',
      );
    }
    return FormationMapSession.fromJson(decoded);
  }

  Future<FormationMapSession?> fetchActiveFormationMapSession() async {
    final uri = AppConfig.activeFormationMapSessionUri();
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load formation map session (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException(
        'Invalid formation map session response',
      );
    }
    return FormationMapSession.fromJson(decoded);
  }

  Future<FormationMapSession> cancelFormationMapSession() async {
    final uri = AppConfig.cancelFormationMapSessionUri();
    if (kDebugMode) {
      debugPrint('ToolService POST $uri');
    }
    final response = await ApiClient.instance
        .sendPost(uri, client: _client, headers: await _headers(jsonBody: true))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        _errorDetail(response.body) ??
            'Failed to cancel formation map session (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException(
        'Invalid formation map session response',
      );
    }
    return FormationMapSession.fromJson(decoded);
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

class AerialMission {
  const AerialMission({
    required this.missionId,
    required this.actionKey,
    required this.status,
    required this.route,
    required this.routeLengthKm,
    required this.flightDurationS,
    required this.createdAt,
    required this.toolId,
    this.flightSpeedKmh,
    this.maxRouteKm,
    this.discoveryChance,
    this.discoveryDistanceM,
    this.flightStartedAt,
    this.flightEndsAt,
    this.toolImageUrl,
    this.discoveredSiteIds = const [],
  });

  final int missionId;
  final String actionKey;
  final String status;
  final List<LatLng> route;
  final double routeLengthKm;
  final int flightDurationS;
  final double? flightSpeedKmh;
  final double? maxRouteKm;
  final double? discoveryChance;
  final double? discoveryDistanceM;
  final DateTime? flightStartedAt;
  final DateTime? flightEndsAt;
  final DateTime createdAt;
  final int toolId;
  final String? toolImageUrl;
  final List<int> discoveredSiteIds;

  int get discoveredSiteCount => discoveredSiteIds.length;

  bool get isActive => status == 'ensuring' || status == 'flying';
  bool get isFlying => status == 'flying';
  bool get isEnsuring => status == 'ensuring';
  bool get isPast =>
      status == 'done' || status == 'failed' || status == 'cancelled';

  factory AerialMission.fromJson(Map<String, dynamic> json) {
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
    final rawIds = json['discovered_site_ids'];
    final discoveredSiteIds = <int>[];
    if (rawIds is List) {
      for (final id in rawIds) {
        if (id is int) {
          discoveredSiteIds.add(id);
        } else if (id is num) {
          discoveredSiteIds.add(id.toInt());
        }
      }
    }
    return AerialMission(
      missionId: json['mission_id'] as int? ?? 0,
      actionKey: json['action_key'] as String? ?? 'aerial_recon',
      status: json['status'] as String? ?? '',
      route: route,
      routeLengthKm: (json['route_length_km'] as num?)?.toDouble() ?? 0,
      flightDurationS: json['flight_duration_s'] as int? ?? 0,
      flightSpeedKmh: (json['flight_speed_kmh'] as num?)?.toDouble(),
      maxRouteKm: (json['max_route_km'] as num?)?.toDouble(),
      discoveryChance: (json['discovery_chance'] as num?)?.toDouble(),
      discoveryDistanceM: (json['discovery_distance_m'] as num?)?.toDouble(),
      flightStartedAt: _parseDate(json['flight_started_at']),
      flightEndsAt: _parseDate(json['flight_ends_at']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now().toUtc(),
      toolId: json['tool_id'] as int? ?? 0,
      toolImageUrl: json['tool_image_url'] as String?,
      discoveredSiteIds: discoveredSiteIds,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    // Backend stores/sends naive UTC (no Z). Treat missing timezone as UTC so
    // flight progress is not shifted into the past by the device offset.
    final hasTz =
        value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    final parsed = DateTime.tryParse(hasTz ? value : '${value}Z');
    return parsed?.toUtc();
  }
}

class GuidanceSession {
  const GuidanceSession({
    required this.sessionId,
    required this.actionKey,
    required this.status,
    required this.toolId,
    required this.durationMinutes,
    required this.startedAt,
    required this.expiresAt,
    this.discoveryChance,
    this.directionExactness,
    this.distanceExactness,
    this.cancelledAt,
  });

  final int sessionId;
  final String actionKey;
  final String status;
  final int toolId;
  final double? discoveryChance;
  final double? directionExactness;
  final double? distanceExactness;
  final int durationMinutes;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? cancelledAt;

  bool get isActive => status == 'active';
  bool get isExpired => !isActive || DateTime.now().toUtc().isAfter(expiresAt);

  factory GuidanceSession.fromJson(Map<String, dynamic> json) {
    return GuidanceSession(
      sessionId: json['session_id'] as int? ?? 0,
      actionKey: json['action_key'] as String? ?? '',
      status: json['status'] as String? ?? '',
      toolId: json['tool_id'] as int? ?? 0,
      discoveryChance: (json['discovery_chance'] as num?)?.toDouble(),
      directionExactness: (json['direction_exactness'] as num?)?.toDouble(),
      distanceExactness: (json['distance_exactness'] as num?)?.toDouble(),
      durationMinutes: json['duration_minutes'] as int? ?? 15,
      startedAt:
          AerialMission._parseDate(json['started_at']) ??
          DateTime.now().toUtc(),
      expiresAt:
          AerialMission._parseDate(json['expires_at']) ??
          DateTime.now().toUtc(),
      cancelledAt: AerialMission._parseDate(json['cancelled_at']),
    );
  }
}

class FormationMapSession {
  const FormationMapSession({
    required this.sessionId,
    required this.actionKey,
    required this.status,
    required this.toolId,
    required this.durationMinutes,
    required this.accuracy,
    required this.range,
    required this.minRangeM,
    required this.maxRangeM,
    required this.startedAt,
    required this.expiresAt,
    this.cancelledAt,
  });

  final int sessionId;
  final String actionKey;
  final String status;
  final int toolId;
  final int durationMinutes;
  final double accuracy;
  final double range;
  final double minRangeM;
  final double maxRangeM;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? cancelledAt;

  bool get isActive => status == 'active';
  bool get isExpired => !isActive || DateTime.now().toUtc().isAfter(expiresAt);

  double get resolvedRangeM => minRangeM + range * (maxRangeM - minRangeM);

  factory FormationMapSession.fromJson(Map<String, dynamic> json) {
    return FormationMapSession(
      sessionId: json['session_id'] as int? ?? 0,
      actionKey: json['action_key'] as String? ?? '',
      status: json['status'] as String? ?? '',
      toolId: json['tool_id'] as int? ?? 0,
      durationMinutes: json['duration_minutes'] as int? ?? 10,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.75,
      range: (json['range'] as num?)?.toDouble() ?? 0.35,
      minRangeM: (json['min_range_m'] as num?)?.toDouble() ?? 200.0,
      maxRangeM: (json['max_range_m'] as num?)?.toDouble() ?? 2000.0,
      startedAt:
          AerialMission._parseDate(json['started_at']) ??
          DateTime.now().toUtc(),
      expiresAt:
          AerialMission._parseDate(json['expires_at']) ??
          DateTime.now().toUtc(),
      cancelledAt: AerialMission._parseDate(json['cancelled_at']),
    );
  }
}

/// Progress along the route in 0..1 using the same arc-fraction timing as
/// backend discovery scheduling.
double aerialMissionProgressFraction(AerialMission mission, {DateTime? now}) {
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
