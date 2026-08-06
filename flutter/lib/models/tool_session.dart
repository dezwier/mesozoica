import 'package:latlong2/latlong.dart';

/// Unified tool session (aerial flight or timed overlay).
class ToolSession {
  const ToolSession({
    required this.sessionId,
    required this.toolId,
    required this.actionKey,
    required this.status,
    required this.startedAt,
    this.expiresAt,
    this.endedAt,
    this.usedDurationS,
    this.stopReason,
    this.params = const {},
    this.state = const {},
    this.eventsSummary = const ToolSessionEventsSummary(),
    this.toolImageUrl,
  });

  final int sessionId;
  final int toolId;
  final String actionKey;
  final String status;
  final DateTime startedAt;
  final DateTime? expiresAt;
  final DateTime? endedAt;
  final int? usedDurationS;
  final String? stopReason;
  final Map<String, dynamic> params;
  final Map<String, dynamic> state;
  final ToolSessionEventsSummary eventsSummary;
  final String? toolImageUrl;

  /// Live aerial (`pending` / `active`) or timed overlay (`active`).
  bool get isActive => status == 'pending' || status == 'active';

  bool get isPending => status == 'pending';

  /// Aerial session currently in flight (`status == active`).
  bool get isInFlight => status == 'active';
  bool get isPast =>
      status == 'completed' || status == 'cancelled' || status == 'failed';

  bool get isExpired {
    final expires = expiresAt;
    if (expires == null) return !isActive;
    return !isActive || DateTime.now().toUtc().isAfter(expires);
  }

  bool get isManualStop => stopReason == 'manual';
  bool get isExhausted => stopReason == 'exhausted';

  // --- Aerial state ---

  List<LatLng> get route {
    final raw = state['route'];
    if (raw is! List) return const [];
    final out = <LatLng>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final lat = item['lat'];
      final lon = item['lon'];
      if (lat is num && lon is num) {
        out.add(LatLng(lat.toDouble(), lon.toDouble()));
      }
    }
    return out;
  }

  double get routeLengthKm =>
      (state['route_length_km'] as num?)?.toDouble() ?? 0;

  int get flightDurationS => (state['flight_duration_s'] as num?)?.toInt() ?? 0;

  DateTime? get flightStartedAt => parseSessionDate(state['flight_started_at']);

  DateTime? get flightEndsAt => parseSessionDate(state['flight_ends_at']);

  String? get errorMessage => state['error_message'] as String?;

  // --- Params knobs (aerial + timed) ---

  double? get flightSpeedKmh =>
      (params['flight_speed_kmh'] as num?)?.toDouble();

  double? get maxRouteKm => (params['max_route_km'] as num?)?.toDouble();

  double? get flightDiscoveryChance =>
      (params['flight_discovery_chance'] as num?)?.toDouble() ??
      (params['discovery_chance'] as num?)?.toDouble();

  double? get flightDiscoveryDistanceM =>
      (params['flight_discovery_distance_m'] as num?)?.toDouble() ??
      (params['discovery_distance_m'] as num?)?.toDouble();

  /// Back-compat aliases.
  double? get discoveryChance => flightDiscoveryChance;

  double? get discoveryDistanceM => flightDiscoveryDistanceM;

  int get durationMinutes => (params['duration_minutes'] as num?)?.toInt() ?? 0;

  double? get directionExactness =>
      (params['direction_exactness'] as num?)?.toDouble();

  double? get distanceExactness =>
      (params['distance_exactness'] as num?)?.toDouble();

  double get accuracy => (params['accuracy'] as num?)?.toDouble() ?? 0;

  double get range => (params['range'] as num?)?.toDouble() ?? 0;

  double get minRangeM => (params['min_range_m'] as num?)?.toDouble() ?? 0;

  double get maxRangeM => (params['max_range_m'] as num?)?.toDouble() ?? 0;

  double get resolvedRangeM => minRangeM + range * (maxRangeM - minRangeM);

  double get widenessM => (params['wideness_m'] as num?)?.toDouble() ?? 0;

  double get cellSizeM => (params['cell_size_m'] as num?)?.toDouble() ?? 0;

  double get centerLat => (params['center_lat'] as num?)?.toDouble() ?? 0;

  double get centerLon => (params['center_lon'] as num?)?.toDouble() ?? 0;

  double get rangeM => (params['range_m'] as num?)?.toDouble() ?? 0;

  List<int> get discoveredSiteIds => eventsSummary.discoveredSiteIds;

  int get discoveredSiteCount => eventsSummary.discoveredCount;

  int get discoveredCount => eventsSummary.discoveredCount;

  /// Effective duration for history UI (used seconds, else elapsed).
  int get durationS {
    if (usedDurationS != null) return usedDurationS!;
    final start = flightStartedAt ?? startedAt;
    if (isActive) {
      final secs = DateTime.now().toUtc().difference(start).inSeconds;
      return secs < 0 ? 0 : secs;
    }
    final end = endedAt ?? flightEndsAt ?? expiresAt;
    if (end == null) return 0;
    final secs = end.difference(start).inSeconds;
    return secs < 0 ? 0 : secs;
  }

  /// Lifetime battery charge for this row (mirrors backend budget charge).
  int batteryChargeS({DateTime? now}) {
    if (usedDurationS != null) return usedDurationS! < 0 ? 0 : usedDurationS!;
    final clock = now ?? DateTime.now().toUtc();

    final isAerial = actionKey.startsWith('aerial_');
    if (isAerial) {
      final flightS = flightDurationS < 0 ? 0 : flightDurationS;
      final started = flightStartedAt;
      if (isPending) return flightS;
      if (isInFlight && started != null) {
        final elapsed = clock.difference(started).inSeconds;
        if (elapsed <= 0) return 0;
        return elapsed > flightS ? flightS : elapsed;
      }
      final end = endedAt ?? flightEndsAt;
      if (started == null || end == null) return 0;
      final secs = end.difference(started).inSeconds;
      return secs < 0 ? 0 : secs;
    }

    if (isActive && expiresAt != null) {
      final allocated = expiresAt!.difference(startedAt).inSeconds;
      final elapsed = clock.difference(startedAt).inSeconds;
      final capped = elapsed > allocated ? allocated : elapsed;
      return capped < 0 ? 0 : capped;
    }
    final end = endedAt ?? expiresAt;
    if (end == null) return 0;
    final secs = end.difference(startedAt).inSeconds;
    return secs < 0 ? 0 : secs;
  }

  factory ToolSession.fromJson(Map<String, dynamic> json) {
    return ToolSession(
      sessionId: json['session_id'] as int? ?? 0,
      toolId: json['tool_id'] as int? ?? 0,
      actionKey: json['action_key'] as String? ?? '',
      status: json['status'] as String? ?? '',
      startedAt: parseSessionDate(json['started_at']) ?? DateTime.now().toUtc(),
      expiresAt: parseSessionDate(json['expires_at']),
      endedAt: parseSessionDate(json['ended_at']),
      usedDurationS: (json['used_duration_s'] as num?)?.toInt(),
      stopReason: json['stop_reason'] as String?,
      params: _asStringKeyedMap(json['params']),
      state: _asStringKeyedMap(json['state']),
      eventsSummary: ToolSessionEventsSummary.fromJson(
        json['events_summary'] is Map<String, dynamic>
            ? json['events_summary'] as Map<String, dynamic>
            : const {},
      ),
      toolImageUrl: json['tool_image_url'] as String?,
    );
  }
}

class ToolSessionEventsSummary {
  const ToolSessionEventsSummary({
    this.discoveredSiteIds = const [],
    this.discoveredCount = 0,
    this.pendingCount = 0,
    this.missCount = 0,
    this.doneCount = 0,
  });

  final List<int> discoveredSiteIds;
  final int discoveredCount;
  final int pendingCount;
  final int missCount;
  final int doneCount;

  factory ToolSessionEventsSummary.fromJson(Map<String, dynamic> json) {
    final rawIds = json['discovered_site_ids'];
    final ids = <int>[];
    if (rawIds is List) {
      for (final id in rawIds) {
        if (id is int) {
          ids.add(id);
        } else if (id is num) {
          ids.add(id.toInt());
        }
      }
    }
    return ToolSessionEventsSummary(
      discoveredSiteIds: ids,
      discoveredCount:
          (json['discovered_count'] as num?)?.toInt() ?? ids.length,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      missCount: (json['miss_count'] as num?)?.toInt() ?? 0,
      doneCount: (json['done_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Unified card history: a [session] use or a [role] change (e.g. obtained).
class ToolHistoryEntry {
  const ToolHistoryEntry({
    required this.kind,
    required this.at,
    this.session,
    this.roleAction,
  });

  final String kind; // session | role
  final DateTime at;
  final ToolSession? session;
  final String? roleAction;

  bool get isSession => kind == 'session' && session != null;
  bool get isRole => kind == 'role';

  factory ToolHistoryEntry.fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    final roleMap = role is Map
        ? _asStringKeyedMap(role)
        : const <String, dynamic>{};
    final sessionRaw = json['session'];
    return ToolHistoryEntry(
      kind: json['kind'] as String? ?? 'session',
      at:
          parseSessionDate(json['at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      session: sessionRaw is Map
          ? ToolSession.fromJson(_asStringKeyedMap(sessionRaw))
          : null,
      roleAction: roleMap['action'] as String?,
    );
  }
}

class ToolSessionListResponse {
  const ToolSessionListResponse({
    this.toolId,
    this.totalDurationS,
    this.usedDurationS,
    this.remainingDurationS,
    this.items = const [],
    this.history = const [],
  });

  final int? toolId;
  final int? totalDurationS;
  final int? usedDurationS;
  final int? remainingDurationS;
  final List<ToolSession> items;
  final List<ToolHistoryEntry> history;

  factory ToolSessionListResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final rawHistory = json['history'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => ToolSession.fromJson(_asStringKeyedMap(e)))
              .toList(growable: false)
        : const <ToolSession>[];
    final history = rawHistory is List
        ? rawHistory
              .whereType<Map>()
              .map((e) => ToolHistoryEntry.fromJson(_asStringKeyedMap(e)))
              .toList(growable: false)
        : const <ToolHistoryEntry>[];
    return ToolSessionListResponse(
      toolId: (json['tool_id'] as num?)?.toInt(),
      totalDurationS: (json['total_duration_s'] as num?)?.toInt(),
      usedDurationS: (json['used_duration_s'] as num?)?.toInt(),
      remainingDurationS: (json['remaining_duration_s'] as num?)?.toInt(),
      items: items,
      history: history,
    );
  }
}

/// Progress along an aerial route in 0..1 (same arc-fraction timing as backend).
double aerialSessionProgressFraction(ToolSession session, {DateTime? now}) {
  if (session.isPending || session.flightStartedAt == null) return 0;
  final started = session.flightStartedAt!;
  final duration = session.flightDurationS;
  if (duration <= 0) return session.isPast ? 1 : 0;
  final clock = now ?? DateTime.now().toUtc();
  final elapsed = clock.difference(started).inMilliseconds / 1000.0;
  return (elapsed / duration).clamp(0.0, 1.0);
}

/// Backend stores/sends naive UTC (no Z). Treat missing timezone as UTC.
DateTime? parseSessionDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final hasTz =
      value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
  final parsed = DateTime.tryParse(hasTz ? value : '${value}Z');
  return parsed?.toUtc();
}

Map<String, dynamic> _asStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return const {};
}
