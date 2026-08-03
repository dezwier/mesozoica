import '../models/guidance_tool_kind.dart';
import '../models/ridge_glass_kind.dart';
import 'game_config.dart';

/// Apply a level, weather_time, or tool modifier to [base].
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

/// Ordered weather_time modifiers for [paramKey] at [weatherTime] (or empty).
List<ParamModifier> weatherTimeModsForParam({
  required Map<String, Map<String, List<ParamModifier>>> weatherTimeModifiers,
  required String paramKey,
  String? weatherTime,
}) {
  if (weatherTime == null || weatherTime.isEmpty) return const [];
  return weatherTimeModifiers[paramKey]?[weatherTime] ?? const [];
}

double resolveScalarMainParam({
  required double base,
  required List<LevelModifierEntry>? levelEntries,
  required int skillLevel,
  List<ParamModifier>? weatherTimeMods,
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

void _appendModsFor(
  List<ParamModifier> out, {
  required ModifiesMainParams? mods,
  required String paramKey,
  required String actionKey,
  required Set<String> ownedActionKeys,
  required String? activeActionKey,
}) {
  if (mods == null || !mods.affectsSkill('site_discovery')) return;
  if (ownedActionKeys.contains(actionKey)) {
    final owning = mods.paramsFor('owning', 'site_discovery')[paramKey];
    if (owning != null) out.add(owning);
  }
  if (activeActionKey == actionKey) {
    final using = mods.paramsFor('using', 'site_discovery')[paramKey];
    if (using != null) out.add(using);
  }
}

/// Owning + active-using tool modifiers for one site_discovery main param.
List<ParamModifier> siteDiscoveryToolModsForParam({
  required String paramKey,
  Set<String> ownedActionKeys = const {},
  String? activeActionKey,
}) {
  if (!GameConfig.isLoaded) return const [];
  final tools = GameConfig.instance.toolActions;
  final out = <ParamModifier>[];

  for (final kind in GuidanceToolKind.values) {
    _appendModsFor(
      out,
      mods: tools.guidanceConfigFor(kind.actionKey).modifiesMainParams,
      paramKey: paramKey,
      actionKey: kind.actionKey,
      ownedActionKeys: ownedActionKeys,
      activeActionKey: activeActionKey,
    );
  }
  _appendModsFor(
    out,
    mods: tools.ridgeGlass.modifiesMainParams,
    paramKey: paramKey,
    actionKey: RidgeGlassKind.actionKey,
    ownedActionKeys: ownedActionKeys,
    activeActionKey: activeActionKey,
  );
  return out;
}

/// Effective walk-in / dwell discover radius after level + weather_time + tools.
double resolveSiteDiscoveryVisibilityDistanceM({
  required int skillLevel,
  String? weatherTime,
  Set<String> ownedActionKeys = const {},
  String? activeActionKey,
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
  );
  for (final mod in siteDiscoveryToolModsForParam(
    paramKey: 'visibility_distance_m',
    ownedActionKeys: ownedActionKeys,
    activeActionKey: activeActionKey,
  )) {
    value = applyMainParamModifier(value, op: mod.op, value: mod.value);
  }
  return value;
}

/// Effective site-survey accuracy params: base → level → weather_time → tools.
///
/// Keys: `dino_accuracy`, `fossil_accuracy`, `completeness_accuracy`,
/// `quality_accuracy`, `depth_accuracy`.
Map<String, double> resolveSiteSurveyAccuracies({
  required int skillLevel,
  String? weatherTime,
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
        weatherTimeMods: weatherTimeModsForParam(
          weatherTimeModifiers: cfg.weatherTimeModifiers,
          paramKey: key,
          weatherTime: weatherTime,
        ),
        toolMod: mods[key],
        clampUnit: true,
      ),
  };
}
