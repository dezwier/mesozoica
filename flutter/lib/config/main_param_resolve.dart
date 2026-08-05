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

/// Apply level keyframes with linear value interpolation between them.
///
/// Below the first keyframe → [base] unchanged. At/above the last → that
/// entry. Between two keyframes → lerp `value` (uses the lower keyframe's
/// `op`). Sparse endpoints (e.g. L1 + L99) are enough for a straight ramp.
double applyLevelModifiers(
  double base,
  List<LevelModifierEntry>? entries,
  int skillLevel,
) {
  if (entries == null || entries.isEmpty) return base;
  final ordered = [...entries]..sort((a, b) => a.level.compareTo(b.level));
  if (skillLevel < ordered.first.level) return base;
  if (skillLevel >= ordered.last.level) {
    return applyMainParamModifier(
      base,
      op: ordered.last.op,
      value: ordered.last.value,
    );
  }
  for (var i = 0; i < ordered.length - 1; i++) {
    final lo = ordered[i];
    final hi = ordered[i + 1];
    if (skillLevel > hi.level) continue;
    if (skillLevel == lo.level || hi.level == lo.level) {
      return applyMainParamModifier(base, op: lo.op, value: lo.value);
    }
    final t = (skillLevel - lo.level) / (hi.level - lo.level);
    final value = lo.value + t * (hi.value - lo.value);
    return applyMainParamModifier(base, op: lo.op, value: value);
  }
  return base;
}

/// Interpolated level modifier at [skillLevel], or null if identity.
///
/// Prefer [applyLevelModifiers] when you only need the resolved float.
LevelModifierEntry? applicableLevelModifier(
  List<LevelModifierEntry>? entries,
  int skillLevel,
) {
  if (entries == null || entries.isEmpty) return null;
  final ordered = [...entries]..sort((a, b) => a.level.compareTo(b.level));
  if (skillLevel < ordered.first.level) return null;
  if (skillLevel >= ordered.last.level) return ordered.last;
  for (var i = 0; i < ordered.length - 1; i++) {
    final lo = ordered[i];
    final hi = ordered[i + 1];
    if (skillLevel > hi.level) continue;
    if (skillLevel == lo.level || hi.level == lo.level) return lo;
    if (skillLevel == hi.level) return hi;
    final t = (skillLevel - lo.level) / (hi.level - lo.level);
    return LevelModifierEntry(
      level: skillLevel,
      op: lo.op,
      value: lo.value + t * (hi.value - lo.value),
    );
  }
  return null;
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
  value = applyLevelModifiers(value, levelEntries, skillLevel);
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
  String skillId = 'field_survey',
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
    base: cfg.discoveryDistanceM,
    levelEntries: cfg.levelModifiers['discovery_distance_m'],
    skillLevel: skillLevel,
    weatherTimeMods: weatherTimeModsForParam(
      weatherTimeModifiers: cfg.weatherTimeModifiers,
      paramKey: 'discovery_distance_m',
      weatherTime: weatherTime,
    ),
    weatherTypeMods: weatherTypeModsForParam(
      weatherTypeModifiers: cfg.weatherTypeModifiers,
      paramKey: 'discovery_distance_m',
      weatherType: weatherType,
    ),
  );
  for (final mod in siteDiscoveryToolModsForParam(
    paramKey: 'discovery_distance_m',
    toolBindings: toolBindings,
    weatherTime: weatherTime,
  )) {
    value = applyMainParamModifier(value, op: mod.op, value: mod.value);
  }
  return value;
}

/// Effective site exploration radius after level + ambient + tools.
double resolveSiteStewardshipSiteVisibilityM({
  required int skillLevel,
  String? weatherTime,
  String? weatherType,
  List<ToolModBinding> toolBindings = const [],
}) {
  if (!GameConfig.isLoaded) return 50.0;
  final cfg = GameConfig.instance.siteStewardship;
  var value = resolveScalarMainParam(
    base: cfg.mainParams.documentationDistanceM,
    levelEntries: cfg.levelModifiers['documentation_distance_m'],
    skillLevel: skillLevel,
    weatherTimeMods: weatherTimeModsForParam(
      weatherTimeModifiers: cfg.weatherTimeModifiers,
      paramKey: 'documentation_distance_m',
      weatherTime: weatherTime,
    ),
    weatherTypeMods: weatherTypeModsForParam(
      weatherTypeModifiers: cfg.weatherTypeModifiers,
      paramKey: 'documentation_distance_m',
      weatherType: weatherType,
    ),
  );
  for (final mod in siteDiscoveryToolModsForParam(
    paramKey: 'documentation_distance_m',
    skillId: 'field_survey',
    toolBindings: toolBindings,
    weatherTime: weatherTime,
  )) {
    value = applyMainParamModifier(value, op: mod.op, value: mod.value);
  }
  return value;
}

/// Effective documentation accuracy: base → level → ambient → tools.
///
/// Single skill baseline (`documentation_accuracy`). Cards apply per-axis
/// [accuracy_noise] separately.
Map<String, double> resolveSiteStewardshipAccuracies({
  required int skillLevel,
  String? weatherTime,
  String? weatherType,
  Map<String, ParamModifier>? toolMods,
}) {
  const key = 'documentation_accuracy';
  if (!GameConfig.isLoaded) {
    return {key: 0.0};
  }
  final cfg = GameConfig.instance.siteStewardship;
  final mp = cfg.mainParams;
  final mods = toolMods ?? const <String, ParamModifier>{};

  return {
    key: resolveScalarMainParam(
      base: mp.documentationAccuracy,
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
