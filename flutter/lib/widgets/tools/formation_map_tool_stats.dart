import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';

/// Stats panel for Formation Map.
class FormationMapToolStats extends StatelessWidget {
  const FormationMapToolStats({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.formationMap;
    final rangeM = cfg.resolvedRangeM;
    final rangeLabel = rangeM >= 1000
        ? '${(rangeM / 1000).toStringAsFixed(1)} km'
        : '${rangeM.round()} m';
    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '${cfg.durationMinutes} min'),
      ToolStatPair(
        'Accuracy',
        cfg.accuracy.toStringAsFixed(
          cfg.accuracy == cfg.accuracy.roundToDouble() ? 0 : 2,
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
        if (cfg.statsExplanation.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(cfg.statsExplanation, style: mutedStyle),
        ],
      ],
    );
  }
}
