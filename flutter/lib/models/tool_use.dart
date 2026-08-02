/// One past or active use of a tool card (session or aerial mission).
class ToolUse {
  const ToolUse({
    required this.id,
    required this.kind,
    required this.actionKey,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.durationS,
    this.stopReason,
    this.params = const {},
    this.result,
  });

  final int id;
  final String kind;
  final String actionKey;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationS;
  final String? stopReason;
  final Map<String, dynamic> params;
  final Map<String, dynamic>? result;

  bool get isActive =>
      status == 'active' || status == 'ensuring' || status == 'flying';

  bool get isManualStop => stopReason == 'manual';
  bool get isExhausted => stopReason == 'exhausted';

  int? get discoveredCount {
    final raw = result?['discovered_count'];
    if (raw is num) return raw.toInt();
    final ids = result?['discovered_site_ids'];
    if (ids is List) return ids.length;
    return null;
  }

  factory ToolUse.fromJson(Map<String, dynamic> json) {
    return ToolUse(
      id: json['id'] as int,
      kind: json['kind'] as String? ?? '',
      actionKey: json['action_key'] as String? ?? '',
      status: json['status'] as String? ?? '',
      startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
      endedAt: json['ended_at'] != null
          ? DateTime.tryParse(json['ended_at'] as String)?.toUtc()
          : null,
      durationS: (json['duration_s'] as num?)?.toInt() ?? 0,
      stopReason: json['stop_reason'] as String?,
      params: (json['params'] as Map<String, dynamic>?) ?? const {},
      result: json['result'] as Map<String, dynamic>?,
    );
  }
}

class ToolUsesResponse {
  const ToolUsesResponse({
    required this.toolId,
    required this.totalDurationS,
    required this.usedDurationS,
    required this.remainingDurationS,
    required this.items,
  });

  final int toolId;
  final int totalDurationS;
  final int usedDurationS;
  final int remainingDurationS;
  final List<ToolUse> items;

  factory ToolUsesResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return ToolUsesResponse(
      toolId: json['tool_id'] as int,
      totalDurationS: (json['total_duration_s'] as num?)?.toInt() ?? 0,
      usedDurationS: (json['used_duration_s'] as num?)?.toInt() ?? 0,
      remainingDurationS: (json['remaining_duration_s'] as num?)?.toInt() ?? 0,
      items: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(ToolUse.fromJson)
              .toList()
          : const [],
    );
  }
}
