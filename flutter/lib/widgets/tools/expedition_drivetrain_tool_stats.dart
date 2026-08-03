import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../config/tool_instance_params.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';
import '../weather/weather_display.dart';

/// Stats panel for Expedition Drivetrain.
///
/// Buff rows come from the tool instance's [modifies_main_params] only.
class ExpeditionDrivetrainToolStats extends StatelessWidget {
  const ExpeditionDrivetrainToolStats({
    super.key,
    this.params,
    this.compact = false,
  });

  final Map<String, dynamic>? params;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = GameConfig.instance.toolActions.expeditionDrivetrain;
    final p = params;
    final durationMinutes =
        (p?['duration_minutes'] as num?)?.toInt() ?? cfg.durationMinutes;
    final mods = modifiesMainParamsFromParams(p);
    final visibilityMod =
        mods?.paramsFor('using', 'site_discovery')['visibility_distance_m'];
    final discoveryMod =
        mods?.paramsFor('using', 'site_discovery')['discovery_chance'];
    final speedMod =
        mods?.paramsFor('using', 'site_discovery')['max_discovery_speed_kmh'];
    final explanation = p?['stats_explanation'] as String? ?? '';

    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
      if (visibilityMod != null)
        ToolStatPair(
          'Visibility',
          WeatherDisplay.formatModifierShort(
            op: visibilityMod.op,
            value: visibilityMod.value,
          ),
        ),
      if (discoveryMod != null)
        ToolStatPair(
          'Discovery rate',
          WeatherDisplay.formatModifierShort(
            op: discoveryMod.op,
            value: discoveryMod.value,
          ),
        ),
      if (speedMod != null)
        ToolStatPair(
          'Max speed',
          WeatherDisplay.formatModifierShort(
            op: speedMod.op,
            value: speedMod.value,
          ),
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
}
