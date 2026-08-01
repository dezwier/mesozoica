import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/game_config.dart';
import '../../controllers/formation_map_controller.dart';
import 'survey_map_hud_shell.dart';
import 'vintage_guidance_compass.dart';

/// Compact vintage map chip: timer, stop, rock-type legend (draggable).
class FormationMapHud extends StatelessWidget {
  const FormationMapHud({super.key});

  static const _maxLegendEntries = 10;

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
      legend: _legendFor(formation),
    );
  }

  List<SurveyLegendEntry> _legendFor(FormationMapController formation) {
    final palette = GameConfig.instance.rockTypeColors;
    final present = <String>{};
    for (final site in formation.discoverableSites) {
      final rock = (site.rockType ?? site.siteTypeRockType)?.trim();
      if (rock == null || rock.isEmpty) continue;
      present.add(rock.toLowerCase());
    }

    // Prefer rocks actually on the overlay; fall back to full palette keys.
    final keys = present.isNotEmpty
        ? (present.toList()..sort())
        : (palette.formationMap.keys.toList()..sort());

    final shown = keys.take(_maxLegendEntries).toList();
    final overflow = keys.length - shown.length;
    final entries = <SurveyLegendEntry>[
      for (final key in shown)
        SurveyLegendEntry(
          label: surveyLegendLabel(key),
          color: surveyRgbColor(palette.forRockType(key)),
        ),
    ];
    if (overflow > 0) {
      entries.add(
        SurveyLegendEntry(
          label: '+$overflow',
          color: VintageInstrumentStyle.brassMuted,
        ),
      );
    }
    return entries;
  }
}
