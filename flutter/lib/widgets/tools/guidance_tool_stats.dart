import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/aerial_mission_flight_stats.dart';

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
    final pairs = <AerialMissionStatPair>[
      AerialMissionStatPair('Duration', '${cfg.durationMinutes} min'),
    ];

    switch (actionKey) {
      case 'proximity_scanner':
        pairs.add(
          AerialMissionStatPair(
            'Exactness',
            _formatExactness(cfg.resolvedDistanceExactness),
          ),
        );
      case 'site_navigator':
        pairs.addAll([
          AerialMissionStatPair(
            'Direction',
            _formatExactness(cfg.resolvedDirectionExactness),
          ),
          AerialMissionStatPair(
            'Distance',
            _formatExactness(cfg.resolvedDistanceExactness),
          ),
          if (cfg.discoveryChance != null)
            AerialMissionStatPair(
              'Site chance',
              _formatChance(cfg.discoveryChance!),
            ),
        ]);
      case 'geo_compass':
      default:
        pairs.addAll([
          AerialMissionStatPair(
            'Exactness',
            _formatExactness(cfg.resolvedDirectionExactness),
          ),
          if (cfg.discoveryChance != null)
            AerialMissionStatPair(
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
    final valueStyle = cardTheme.bodyStyle(fontSize: 13).copyWith(
          fontWeight: FontWeight.w600,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final pair in pairs)
              SizedBox(
                width: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pair.label, style: mutedStyle),
                    Text(pair.value, style: valueStyle),
                  ],
                ),
              ),
          ],
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
