import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';

/// Stats panel for site-guidance tools (compass / proximity / navigator).
class GuidanceToolStats extends StatelessWidget {
  const GuidanceToolStats({
    super.key,
    required this.actionKey,
    this.compact = false,
  });

  final String actionKey;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.guidanceConfigFor(actionKey);
    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '${cfg.durationMinutes} min'),
    ];

    switch (actionKey) {
      case 'proximity_scanner':
        pairs.add(
          ToolStatPair(
            'Exactness',
            _formatExactness(cfg.resolvedDistanceExactness),
          ),
        );
      case 'site_navigator':
        pairs.addAll([
          ToolStatPair(
            'Direction',
            _formatExactness(cfg.resolvedDirectionExactness),
          ),
          ToolStatPair(
            'Distance',
            _formatExactness(cfg.resolvedDistanceExactness),
          ),
          if (cfg.discoveryChance != null)
            ToolStatPair(
              'Site chance',
              _formatChance(cfg.discoveryChance!),
            ),
        ]);
      case 'geo_compass':
      default:
        pairs.addAll([
          ToolStatPair(
            'Exactness',
            _formatExactness(cfg.resolvedDirectionExactness),
          ),
          if (cfg.discoveryChance != null)
            ToolStatPair(
              'Site chance',
              _formatChance(cfg.discoveryChance!),
            ),
        ]);
    }

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

  static String _formatExactness(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);

  static String _formatChance(double value) {
    final pct = (value * 100).round();
    return '$pct%';
  }
}
