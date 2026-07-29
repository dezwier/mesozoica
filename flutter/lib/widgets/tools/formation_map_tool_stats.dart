import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';

/// Stats panel for Formation Map.
class FormationMapToolStats extends StatelessWidget {
  const FormationMapToolStats({
    super.key,
    this.params,
    this.compact = false,
  });

  final Map<String, dynamic>? params;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.formationMap;
    final p = params;
    final durationMinutes =
        (p?['duration_minutes'] as num?)?.toInt() ?? cfg.durationMinutes;
    final accuracy = (p?['accuracy'] as num?)?.toDouble() ?? cfg.accuracy;
    final range = (p?['range'] as num?)?.toDouble() ?? cfg.range;
    final minRangeM = (p?['min_range_m'] as num?)?.toDouble() ?? cfg.minRangeM;
    final maxRangeM = (p?['max_range_m'] as num?)?.toDouble() ?? cfg.maxRangeM;
    final explanation = p?['stats_explanation'] as String? ?? cfg.statsExplanation;
    final rangeM = minRangeM + range * (maxRangeM - minRangeM);
    final rangeLabel = rangeM >= 1000
        ? '${(rangeM / 1000).toStringAsFixed(1)} km'
        : '${rangeM.round()} m';
    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
      ToolStatPair(
        'Accuracy',
        accuracy.toStringAsFixed(
          accuracy == accuracy.roundToDouble() ? 0 : 2,
        ),
      ),
      ToolStatPair('Range', rangeLabel),
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
}
