import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../config/tool_instance_params.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';
import '../weather/weather_display.dart';

/// Stats panel for Ridge Glass.
///
/// Buff rows come from the tool instance's [modifies_main_params] only.
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
    // Instance params only — never fall back to live YAML for buffs.
    final mods = modifiesMainParamsFromParams(p);
    final visibilityMod =
        mods?.paramsFor('using', 'site_discovery')['visibility_distance_m'];
    final discoveryMod =
        mods?.paramsFor('using', 'site_discovery')['discovery_chance'];
    final explanation = p?['stats_explanation'] as String? ?? '';

    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
      if (visibilityMod != null)
        ToolStatPair(
          'Visibility',
          _formatMod(visibilityMod, meters: true),
        ),
      if (discoveryMod != null)
        ToolStatPair(
          'Discovery rate',
          _formatMod(discoveryMod, chance: true),
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

  static String _formatMod(
    ParamModifier mod, {
    bool meters = false,
    bool chance = false,
  }) {
    switch (mod.op) {
      case 'add':
        if (chance) {
          final pct = (mod.value * 100).round();
          return pct >= 0 ? '+$pct%' : '$pct%';
        }
        if (meters) {
          final m = mod.value.round();
          return m >= 0 ? '+$m m' : '$m m';
        }
        break;
      case 'replace':
        if (chance) return '→ ${(mod.value * 100).round()}%';
        if (meters) return '→ ${mod.value.round()} m';
        break;
    }
    return WeatherDisplay.formatModifierShort(op: mod.op, value: mod.value);
  }
}
