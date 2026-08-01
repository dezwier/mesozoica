import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/formation_map_controller.dart';
import 'survey_map_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip: timer, stop, rock-type legend (draggable).
class FormationMapHud extends StatelessWidget {
  const FormationMapHud({super.key});

  @override
  Widget build(BuildContext context) {
    final formation = context.watch<FormationMapController>();
    if (!formation.isActive) return const SizedBox.shrink();

    return SurveyMapHudShell(
      icon: Icon(
        Icons.grid_on,
        size: 22,
        color: VintageInstrumentStyle.brassRim,
      ),
      remainingListenable: formation.remainingListenable,
      onStop: () => formation.stop(),
      collapseLegendToTwoLines: true,
      legend: _legendFor(formation),
    );
  }

  List<SurveyLegendEntry> _legendFor(FormationMapController formation) {
    final palette = GameConfig.instance.rockTypeColors;
    final counts = <String, int>{};
    for (final site in formation.discoverableSites) {
      final rock = (site.rockType ?? site.siteTypeRockType)?.trim();
      if (rock == null || rock.isEmpty) continue;
      final key = rock.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // Most common rocks first; fall back to palette A–Z when none are loaded.
    final keys = counts.isNotEmpty
        ? (counts.keys.toList()
          ..sort((a, b) {
            final byCount = counts[b]!.compareTo(counts[a]!);
            if (byCount != 0) return byCount;
            return a.compareTo(b);
          }))
        : (palette.formationMap.keys.toList()..sort());

    return [
      for (final key in keys)
        SurveyLegendEntry(
          label: surveyLegendLabel(key),
          color: surveyRgbColor(palette.forRockType(key)),
        ),
    ];
  }
}
