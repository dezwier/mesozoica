import 'game_config.dart';
import 'tool_instance_params.dart';

/// Apply a level, ambient, or tool modifier to [base].
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

/// Ordered ambient modifiers for [paramKey] at [key] (or empty).
List<ParamModifier> ambientModsForParam({
  required Map<String, Map<String, List<ParamModifier>>> modifiers,
  required String paramKey,
  String? key,
}) {
  if (key == null || key.isEmpty) return const [];
  final normalized = key == 'sunny' ? 'clear' : key;
  return modifiers[paramKey]?[normalized] ?? const [];
}

/// Ordered weather_time modifiers for [paramKey] at [weatherTime] (or empty).
List<ParamModifier> weatherTimeModsForParam({
  required Map<String, Map<String, List<ParamModifier>>> weatherTimeModifiers,
  required String paramKey,
  String? weatherTime,
}) =>
    ambientModsForParam(
      modifiers: weatherTimeModifiers,
      paramKey: paramKey,
      key: weatherTime,
    );

List<ParamModifier> weatherTypeModsForParam({
  required Map<String, Map<String, List<ParamModifier>>> weatherTypeModifiers,
  required String paramKey,
  String? weatherType,
}) =>
    ambientModsForParam(
      modifiers: weatherTypeModifiers,
      paramKey: paramKey,
      key: weatherType,
    );

double resolveScalarMainParam({
  required double base,
  required List<LevelModifierEntry>? levelEntries,
  required int skillLevel,
  List<ParamModifier>? weatherTimeMods,
  List<ParamModifier>? weatherTypeMods,
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
  for (final mod in weatherTimeMods ?? const <ParamModifier>[]) {
    value = applyMainParamModifier(value, op: mod.op, value: mod.value);
  }
  for (final mod in weatherTypeMods ?? const <ParamModifier>[]) {
    value = applyMainParamModifier(value, op: mod.op, value: mod.value);
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

/// Owning + using modifiers from tool *instances* (never YAML baselines).
List<ParamModifier> siteDiscoveryToolModsForParam({
  required String paramKey,
  List<ToolModBinding> toolBindings = const [],
  String skillId = 'site_discovery',
  String? weatherTime,
}) {
  final out = <ParamModifier>[];
  for (final binding in toolBindings) {
    final mods = binding.mods;
    if (!mods.affectsSkill(skillId)) continue;
    if (binding.applyOwning) {
      final owning = mods.paramsFor('owning', skillId)[paramKey];
      if (owning != null) out.add(owning);
    }
    if (binding.applyUsing) {
      if (!binding.usingAllowedForWeatherTime(weatherTime)) continue;
      final using = mods.paramsFor('using', skillId)[paramKey];
      if (using != null) out.add(using);
    }
  }
  return out;
}

/// Effective walk-in / dwell discover radius after level + ambient + tools.
double resolveSiteDiscoveryVisibilityDistanceM({
  required int skillLevel,
  String? weatherTime,
  String? weatherType,
  List<ToolModBinding> toolBindings = const [],
}) {
  if (!GameConfig.isLoaded) return 20.0;
  final cfg = GameConfig.instance.siteDiscovery;
  var value = resolveScalarMainParam(
    base: cfg.visibilityDistanceM,
    levelEntries: cfg.levelModifiers['visibility_distance_m'],
    skillLevel: skillLevel,
    weatherTimeMods: weatherTimeModsForParam(
      weatherTimeModifiers: cfg.weatherTimeModifiers,
      paramKey: 'visibility_distance_m',
      weatherTime: weatherTime,
    ),
    weatherTypeMods: weatherTypeModsForParam(
      weatherTypeModifiers: cfg.weatherTypeModifiers,
      paramKey: 'visibility_distance_m',
      weatherType: weatherType,
    ),
  );
  for (final mod in siteDiscoveryToolModsForParam(
    paramKey: 'visibility_distance_m',
    toolBindings: toolBindings,
    weatherTime: weatherTime,
  )) {
    value = applyMainParamModifier(value, op: mod.op, value: mod.value);
  }
  return value;
}

/// Effective site-dimension accuracy params: base → level → ambient → tools.
///
/// Keys: `dino_accuracy`, `fossil_accuracy`, `completeness_accuracy`,
/// `quality_accuracy`, `depth_accuracy`.
Map<String, double> resolveSiteStewardshipAccuracies({
  required int skillLevel,
  String? weatherTime,
  String? weatherType,
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
  final cfg = GameConfig.instance.siteStewardship;
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
        weatherTimeMods: weatherTimeModsForParam(
          weatherTimeModifiers: cfg.weatherTimeModifiers,
          paramKey: key,
          weatherTime: weatherTime,
        ),
        weatherTypeMods: weatherTypeModsForParam(
          weatherTypeModifiers: cfg.weatherTypeModifiers,
          paramKey: key,
          weatherType: weatherType,
        ),
        toolMod: mods[key],
        clampUnit: true,
      ),
  };
}
