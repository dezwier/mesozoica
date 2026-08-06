import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../config/tool_instance_params.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';
import '../weather/weather_display.dart';

/// Stats panel for site-guidance tools (compass / proximity / navigator).
class GuidanceToolStats extends StatelessWidget {
  const GuidanceToolStats({
    super.key,
    required this.actionKey,
    this.params,
    this.compact = false,
  });

  final String actionKey;
  final Map<String, dynamic>? params;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.guidanceConfigFor(actionKey);
    final p = params;
    final durationMinutes =
        (p?['duration_minutes'] as num?)?.toInt() ?? cfg.durationMinutes;
    final exactness = (p?['exactness'] as num?)?.toDouble();
    final directionExactness = (p?['direction_exactness'] as num?)?.toDouble();
    final distanceExactness = (p?['distance_exactness'] as num?)?.toDouble();
    final discoveryMod = modifiesMainParamsFromParams(
      p,
    )?.paramsFor('using', 'field_survey')['discovery_chance'];
    final discoveryChance =
        (p?['discovery_chance'] as num?)?.toDouble() ??
        (discoveryMod?.op == 'replace' ? discoveryMod?.value : null) ??
        cfg.discoveryChance;
    final explanation =
        p?['stats_explanation'] as String? ?? cfg.statsExplanation;
    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
    ];

    switch (actionKey) {
      case 'proximity_scanner':
        pairs.add(
          ToolStatPair(
            'Exactness',
            _formatExactness(
              distanceExactness ?? exactness ?? cfg.resolvedDistanceExactness,
            ),
          ),
        );
      case 'site_navigator':
        pairs.addAll([
          ToolStatPair(
            'Direction',
            _formatExactness(
              directionExactness ?? exactness ?? cfg.resolvedDirectionExactness,
            ),
          ),
          ToolStatPair(
            'Distance',
            _formatExactness(
              distanceExactness ?? exactness ?? cfg.resolvedDistanceExactness,
            ),
          ),
          if (discoveryMod != null)
            ToolStatPair(
              'Discovery chance',
              discoveryMod.op == 'replace'
                  ? '→ ${_formatChance(discoveryMod.value)}'
                  : WeatherDisplay.formatModifierShort(
                      op: discoveryMod.op,
                      value: discoveryMod.value,
                    ),
            )
          else if (discoveryChance != null)
            ToolStatPair('Discovery chance', _formatChance(discoveryChance)),
        ]);
      case 'geo_compass':
      default:
        pairs.addAll([
          ToolStatPair(
            'Exactness',
            _formatExactness(
              directionExactness ?? exactness ?? cfg.resolvedDirectionExactness,
            ),
          ),
          if (discoveryMod != null)
            ToolStatPair(
              'Discovery chance',
              discoveryMod.op == 'replace'
                  ? '→ ${_formatChance(discoveryMod.value)}'
                  : WeatherDisplay.formatModifierShort(
                      op: discoveryMod.op,
                      value: discoveryMod.value,
                    ),
            )
          else if (discoveryChance != null)
            ToolStatPair('Discovery chance', _formatChance(discoveryChance)),
        ]);
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

  static String _formatExactness(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);

  static String _formatChance(double value) {
    final pct = (value * 100).round();
    return '$pct%';
  }
}
