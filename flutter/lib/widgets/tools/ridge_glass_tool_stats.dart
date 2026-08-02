import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';

/// Stats panel for Ridge Glass.
class RidgeGlassToolStats extends StatelessWidget {
  const RidgeGlassToolStats({
    super.key,
    this.params,
    this.compact = false,
  });

  final Map<String, dynamic>? params;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.ridgeGlass;
    final p = params;
    final durationMinutes =
        (p?['duration_minutes'] as num?)?.toInt() ?? cfg.durationMinutes;
    final visibilityAdd =
        _modValue(p, 'visibility_distance_m') ?? cfg.addedVisibilityRangeM;
    final discoveryAdd =
        _modValue(p, 'discovery_chance') ?? cfg.addedDiscoveryRate;
    final explanation =
        p?['stats_explanation'] as String? ?? cfg.statsExplanation;

    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
      if (visibilityAdd != null)
        ToolStatPair('Visibility', '+${visibilityAdd.round()} m'),
      if (discoveryAdd != null)
        ToolStatPair(
          'Discovery rate',
          '+${(discoveryAdd * 100).round()}%',
        ),
    ];

    if (compact) {
      return Text(
        pairs.map((r) => '${r.label} ${r.value}').join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final cardTheme = DinoCardTheme.of(context);
    final mutedStyle = cardTheme.bodyStyle(fontSize: 11).copyWith(
          color: cardTheme.cardTextMuted,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToolStatGrid(
          pairs: pairs.map((p) => ToolStatPair(p.label, p.value)).toList(),
        ),
        if (explanation.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(explanation, style: mutedStyle),
        ],
      ],
    );
  }

  static double? _modValue(Map<String, dynamic>? params, String paramKey) {
    final raw = params?['modifies_main_params'];
    if (raw is! Map) return null;
    final using = raw['using'];
    if (using is! Map) return null;
    final skill = using['site_discovery'];
    if (skill is! Map) return null;
    final entry = skill[paramKey];
    if (entry is! Map) return null;
    if (entry['op'] != 'add') return null;
    final value = entry['value'];
    if (value is num) return value.toDouble();
    return null;
  }
}
