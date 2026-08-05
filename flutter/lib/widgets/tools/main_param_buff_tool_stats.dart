import 'package:flutter/material.dart';

import '../../config/game_config.dart';
import '../../config/tool_instance_params.dart';
import '../../theme/dino_card_theme.dart';
import '../tools/tool_stat_row.dart';
import '../weather/weather_display.dart';

/// Stats panel for timed main-param buff tools (Ridge / Drive / Nocturne).
///
/// Buff rows come from the tool instance's [modifies_main_params] only.
class MainParamBuffToolStats extends StatelessWidget {
  const MainParamBuffToolStats({
    super.key,
    this.params,
    this.yamlFallback,
    this.compact = false,
  });

  final Map<String, dynamic>? params;
  final Map<String, dynamic>? yamlFallback;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = params;
    final fallback = yamlFallback ?? const <String, dynamic>{};
    final durationMinutes = (p?['duration_minutes'] as num?)?.toInt() ??
        (fallback['duration_minutes'] as num?)?.toInt() ??
        60;
    // Instance params only — never fall back to live YAML for buffs.
    final mods = modifiesMainParamsFromParams(p);
    final visibilityMod =
        mods?.paramsFor('using', 'field_survey')['discovery_distance_m'];
    final discoveryMod =
        mods?.paramsFor('using', 'field_survey')['discovery_chance'];
    final speedMod =
        mods?.paramsFor('using', 'field_survey')['discovery_max_speed_kmh'];
    final documentationDistanceMod =
        mods?.paramsFor('using', 'field_survey')['documentation_distance_m'];
    final explanation =
        (p?['stats_explanation'] as String?)?.trim().isNotEmpty == true
            ? p!['stats_explanation'] as String
            : (fallback['stats_explanation'] as String? ?? '');
    final activeTimes = p?['active_weather_times'] as List? ??
        fallback['active_weather_times'] as List?;

    final pairs = <ToolStatPair>[
      ToolStatPair('Duration', '$durationMinutes min'),
      if (activeTimes != null && activeTimes.isNotEmpty)
        ToolStatPair(
          'Active',
          activeTimes.map((e) => e.toString()).join(', '),
        ),
      if (visibilityMod != null)
        ToolStatPair(
          'Discovery distance',
          _formatMod(visibilityMod, meters: true),
        ),
      if (discoveryMod != null)
        ToolStatPair(
          'Discovery chance',
          _formatMod(discoveryMod, chance: true),
        ),
      if (documentationDistanceMod != null)
        ToolStatPair(
          'Documentation distance',
          _formatMod(documentationDistanceMod, meters: true),
        ),
      if (speedMod != null)
        ToolStatPair(
          'Discovery max speed',
          _formatMod(speedMod),
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

/// Back-compat aliases.
typedef RidgeGlassToolStats = MainParamBuffToolStats;
typedef ExpeditionDrivetrainToolStats = MainParamBuffToolStats;
