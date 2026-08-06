import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';

/// Stats panel for Formation Map.
class FormationMapToolStats extends StatelessWidget {
  const FormationMapToolStats({super.key, this.params, this.compact = false});

  final Map<String, dynamic>? params;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.formationMap;
    final p = params;
    final durationMinutes =
        (p?['duration_minutes'] as num?)?.toInt() ?? cfg.durationMinutes;
    final accuracy = (p?['accuracy'] as num?)?.toDouble() ?? cfg.accuracy;
    final widenessM = (p?['wideness_m'] as num?)?.toDouble() ?? cfg.widenessM;
    final explanation =
        p?['stats_explanation'] as String? ?? cfg.statsExplanation;
    final centerLat = (p?['center_lat'] as num?)?.toDouble();
    final centerLon = (p?['center_lon'] as num?)?.toDouble();
    final widenessLabel = widenessM >= 1000
        ? '${(widenessM / 1000).toStringAsFixed(1)} km'
        : '${widenessM.round()} m';
    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
      ToolStatPair(
        'Accuracy',
        accuracy.toStringAsFixed(accuracy == accuracy.roundToDouble() ? 0 : 2),
      ),
      ToolStatPair('Wideness', widenessLabel),
    ];
    if (centerLat != null && centerLon != null) {
      pairs.add(
        ToolStatPair(
          'Center',
          '${centerLat.toStringAsFixed(4)}, ${centerLon.toStringAsFixed(4)}',
        ),
      );
    }

    if (compact) {
      return Text(
        pairs.map((r) => '${r.label} ${r.value}').join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final cardTheme = DinoCardTheme.of(context);
    final mutedStyle = cardTheme
        .bodyStyle(fontSize: 11)
        .copyWith(color: cardTheme.cardTextMuted);
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
