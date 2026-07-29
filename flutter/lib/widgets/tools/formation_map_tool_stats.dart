import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/aerial_mission_flight_stats.dart';

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
    final pairs = <AerialMissionStatPair>[
      AerialMissionStatPair('Duration', '${cfg.durationMinutes} min'),
      AerialMissionStatPair(
        'Accuracy',
        cfg.accuracy.toStringAsFixed(
          cfg.accuracy == cfg.accuracy.roundToDouble() ? 0 : 2,
        ),
      ),
      AerialMissionStatPair('Range', rangeLabel),
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
}
