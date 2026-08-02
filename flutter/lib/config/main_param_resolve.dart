import 'game_config.dart';

/// Apply a level or tool modifier to [base].
double applyMainParamModifier(
  double base, {
  required String op,
  required double value,
}) {
  switch (op) {
    case 'replace':
      return value;
    case 'add':
      return base + value;
    case 'multiply':
      return base * value;
    default:
      return base;
  }
}

/// Highest entry with `level <= skillLevel` wins (identity if none).
LevelModifierEntry? applicableLevelModifier(
  List<LevelModifierEntry>? entries,
  int skillLevel,
) {
  if (entries == null || entries.isEmpty) return null;
  LevelModifierEntry? best;
  for (final entry in entries) {
    if (entry.level > skillLevel) continue;
    if (best == null || entry.level > best.level) best = entry;
  }
  return best;
}

double resolveScalarMainParam({
  required double base,
  required List<LevelModifierEntry>? levelEntries,
  required int skillLevel,
  ParamModifier? toolMod,
  bool clampUnit = false,
}) {
  var value = base;
  final levelMod = applicableLevelModifier(levelEntries, skillLevel);
  if (levelMod != null) {
    value = applyMainParamModifier(
      value,
      op: levelMod.op,
      value: levelMod.value,
    );
  }
  if (toolMod != null) {
    value = applyMainParamModifier(
      value,
      op: toolMod.op,
      value: toolMod.value,
    );
  }
  if (clampUnit) return value.clamp(0.0, 1.0);
  return value;
}

/// Effective site-survey accuracy params: base → level → optional tool mods.
///
/// Keys: `dino_accuracy`, `fossil_accuracy`, `completeness_accuracy`,
/// `quality_accuracy`, `depth_accuracy`.
Map<String, double> resolveSiteSurveyAccuracies({
  required int skillLevel,
  Map<String, ParamModifier>? toolMods,
}) {
  const keys = <String>[
    'dino_accuracy',
    'fossil_accuracy',
    'completeness_accuracy',
    'quality_accuracy',
    'depth_accuracy',
  ];
  if (!GameConfig.isLoaded) {
    return {for (final key in keys) key: 0.0};
  }
  final cfg = GameConfig.instance.siteSurvey;
  final mp = cfg.mainParams;
  final mods = toolMods ?? const <String, ParamModifier>{};
  final bases = <String, double>{
    'dino_accuracy': mp.dinoAccuracy,
    'fossil_accuracy': mp.fossilAccuracy,
    'completeness_accuracy': mp.completenessAccuracy,
    'quality_accuracy': mp.qualityAccuracy,
    'depth_accuracy': mp.depthAccuracy,
  };

  return {
    for (final key in keys)
      key: resolveScalarMainParam(
        base: bases[key]!,
        levelEntries: cfg.levelModifiers[key],
        skillLevel: skillLevel,
        toolMod: mods[key],
        clampUnit: true,
      ),
  };
}
