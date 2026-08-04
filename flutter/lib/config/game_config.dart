import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// Shared game-mechanics control board (YAML under assets/game_config/).
///
/// Source of truth lives at `backend/app/game_config/` and is linked into
/// Flutter assets. Call [GameConfig.load] once in `main()` before `runApp`.
class GameConfig {
  GameConfig({
    required this.siteGeneration,
    required this.fieldSurvey,
    required this.boneQuarry,
    required this.scienceHall,
    required this.toolActions,
    required this.periodColors,
    required this.rockTypeColors,
    required this.leveling,
  });

  final SiteGenerationConfig siteGeneration;
  final FieldSurveyConfig fieldSurvey;
  final SkillStubConfig boneQuarry;
  final SkillStubConfig scienceHall;
  final ToolActionsConfig toolActions;
  final PeriodColorsConfig periodColors;
  final RockTypeColorsConfig rockTypeColors;
  final LevelingConfig leveling;

  /// Back-compat aliases for call sites during migration.
  FieldSurveyConfig get siteDiscovery => fieldSurvey;
  FieldSurveyConfig get siteStewardship => fieldSurvey;
  FieldSurveyConfig get fossilGeneration => fieldSurvey;
  SkillStubConfig get fossilDetection => boneQuarry;

  Object? skillDomain(String skillId) {
    switch (skillId) {
      case 'field_survey':
      case 'site_discovery':
      case 'site_stewardship':
      case 'site_clearing':
        return fieldSurvey;
      case 'bone_quarry':
      case 'fossil_detection':
      case 'fossil_excavation':
      case 'fossil_transport':
      case 'fossil_curation':
      case 'fossil_discovery':
        return boneQuarry;
      case 'science_hall':
      case 'fossil_preparation':
      case 'fossil_analysis':
      case 'dinosaur_modelling':
      case 'dinosaur_mounting':
      case 'academic_publishing':
        return scienceHall;
      default:
        return null;
    }
  }

  static GameConfig? _instance;

  /// Loaded singleton. Throws if [load] / [loadFromYamlStrings] was not called.
  static GameConfig get instance {
    final value = _instance;
    if (value == null) {
      throw StateError('GameConfig.load() must be called before use');
    }
    return value;
  }

  static bool get isLoaded => _instance != null;

  /// Replace the singleton (tests).
  static void debugSetInstance(GameConfig config) {
    _instance = config;
  }

  static void debugReset() {
    _instance = null;
  }

  static const _assetPrefix = 'assets/game_config';

  /// Load all domain YAML files from Flutter assets.
  static Future<GameConfig> load() async {
    Future<String> read(String name) =>
        rootBundle.loadString('$_assetPrefix/$name');

    final config = loadFromYamlStrings(
      siteGenerationYaml: await read('site_generation.yaml'),
      fieldSurveyYaml: await read('01_field_survey.yaml'),
      boneQuarryYaml: await read('02_bone_quarry.yaml'),
      scienceHallYaml: await read('03_science_hall.yaml'),
      toolActionsYaml: await read('tool_actions.yaml'),
      periodColorsYaml: await read('period_colors.yaml'),
      rockTypeColorsYaml: await read('rock_type_colors.yaml'),
      levelingYaml: await read('leveling.yaml'),
    );
    _instance = config;
    return config;
  }

  /// Parse domain YAML strings (also used by unit tests).
  static GameConfig loadFromYamlStrings({
    required String siteGenerationYaml,
    required String fieldSurveyYaml,
    required String boneQuarryYaml,
    required String scienceHallYaml,
    required String toolActionsYaml,
    required String periodColorsYaml,
    required String rockTypeColorsYaml,
    required String levelingYaml,
  }) {
    final config = fromDocuments(<String, dynamic>{
      'site_generation': loadYaml(siteGenerationYaml),
      'field_survey': loadYaml(fieldSurveyYaml),
      'bone_quarry': loadYaml(boneQuarryYaml),
      'science_hall': loadYaml(scienceHallYaml),
      'tool_actions': loadYaml(toolActionsYaml),
      'period_colors': loadYaml(periodColorsYaml),
      'rock_type_colors': loadYaml(rockTypeColorsYaml),
      'leveling': loadYaml(levelingYaml),
    });
    _instance = config;
    return config;
  }

  /// Build from raw document maps keyed by document id.
  ///
  /// Accepts either YAML-decoded (`YamlMap`) or JSON-decoded (`Map`) values —
  /// every `fromYaml` factory below duck-types on `Map` / `List`. This is the
  /// shared seam for the bundled assets, the local cache, and the config API.
  /// Does not set the singleton.
  static GameConfig fromDocuments(Map<String, dynamic> documents) {
    Map<String, dynamic> doc(String id) {
      if (!documents.containsKey(id)) {
        throw FormatException('Missing game config document: $id');
      }
      return _asMap(documents[id]);
    }

    return GameConfig(
      siteGeneration: SiteGenerationConfig.fromYaml(doc('site_generation')),
      fieldSurvey: FieldSurveyConfig.fromYaml(doc('field_survey')),
      boneQuarry: SkillStubConfig.fromYaml(doc('bone_quarry')),
      scienceHall: SkillStubConfig.fromYaml(doc('science_hall')),
      toolActions: ToolActionsConfig.fromYaml(doc('tool_actions')),
      periodColors: PeriodColorsConfig.fromYaml(doc('period_colors')),
      rockTypeColors: RockTypeColorsConfig.fromYaml(doc('rock_type_colors')),
      leveling: LevelingConfig.fromYaml(doc('leveling')),
    );
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('Expected YAML mapping, got ${raw.runtimeType}');
  }
}

class SiteGenerationConfig {
  const SiteGenerationConfig({required this.cellSizeM, required this.client});

  /// Density square size from YAML `lazy.cell_size_m` (walk ensure cell).
  final double cellSizeM;
  final SiteGenerationClientConfig client;

  factory SiteGenerationConfig.fromYaml(Map<String, dynamic> yaml) {
    final lazy = GameConfig._asMap(yaml['lazy']);
    return SiteGenerationConfig(
      cellSizeM: _asDouble(lazy['cell_size_m'], 500.0),
      client: SiteGenerationClientConfig.fromYaml(
        GameConfig._asMap(yaml['client']),
      ),
    );
  }
}

class SiteGenerationClientConfig {
  const SiteGenerationClientConfig({required this.nearbyRadiusKm});

  final double nearbyRadiusKm;

  factory SiteGenerationClientConfig.fromYaml(Map<String, dynamic> yaml) {
    return SiteGenerationClientConfig(
      nearbyRadiusKm: _asDouble(yaml['nearby_radius_km'], 1.0),
    );
  }
}

class FieldSurveyConfig {
  const FieldSurveyConfig({
    required this.skillId,
    required this.mainParams,
    required this.levelModifiers,
    required this.weatherTimeModifiers,
    required this.weatherTypeModifiers,
    required this.client,
    required this.dinoCount,
    required this.fossilCount,
    required this.depthWeights,
    required this.completenessWeights,
    required this.qualityWeights,
    required this.oddNoise,
    required this.accuracyNoise,
    required this.defaults,
  });

  final String skillId;
  final FieldSurveyMainParams mainParams;
  final Map<String, List<LevelModifierEntry>> levelModifiers;

  /// param → period (dawn|day|dusk|golden_hour|night) → ordered modifiers.
  final Map<String, Map<String, List<ParamModifier>>> weatherTimeModifiers;

  /// param → weather type (clear|cloudy|…) → ordered modifiers.
  final Map<String, Map<String, List<ParamModifier>>> weatherTypeModifiers;
  final FieldSurveyClientConfig client;

  /// Fixed global distribution tables (not subject to level/tool multipliers).
  final List<DinoCountThreshold> dinoCount;
  final Map<int, double> fossilCount;
  final List<FossilDepthBucket> depthWeights;
  final Map<String, double> completenessWeights;
  final Map<String, double> qualityWeights;
  final FossilOddNoiseConfig oddNoise;
  final AccuracyNoiseConfig accuracyNoise;
  final FossilGenerationDefaults defaults;

  double get visibilityDistanceM => mainParams.visibilityDistanceM;
  double get discoveryChance => mainParams.discoveryChance;
  double get maxDiscoverySpeedKmh => mainParams.maxDiscoverySpeedKmh;
  double get siteDiscoveryXp => mainParams.siteDiscoveryXp;
  double get firstDiscoveryXp => mainParams.firstDiscoveryXp;
  double get active100mXp => mainParams.active100mXp;
  double get passiveKmXp => mainParams.passiveKmXp;
  double get successfulSiteDisguiseXp => mainParams.successfulSiteDisguiseXp;
  double get siteExplorationXp => mainParams.siteExplorationXp;
  double get siteDocumentationXp => mainParams.siteDocumentationXp;
  double get firstDocumentationXp => mainParams.firstDocumentationXp;
  double get siteIdentificationXp => mainParams.siteIdentificationXp;
  double get siteVisibilityM => mainParams.siteVisibilityM;
  double get rivalDiscovery => mainParams.rivalDiscovery;

  /// Back-compat alias.
  double get maxDistanceM => visibilityDistanceM;

  /// Back-compat aliases for distribution tables.
  List<DinoCountThreshold> get dinoCountThresholds => dinoCount;
  Map<int, double> get cardCountWeights => fossilCount;
  List<FossilDepthBucket> get depthBuckets => depthWeights;

  factory FieldSurveyConfig.fromYaml(Map<String, dynamic> yaml) {
    final main = GameConfig._asMap(yaml['main_params']);
    final rawBuckets = yaml['depth_weights'] ?? yaml['depth_buckets'];
    final buckets = <FossilDepthBucket>[];
    if (rawBuckets is List) {
      for (final entry in rawBuckets) {
        if (entry is Map) {
          buckets.add(
            FossilDepthBucket(
              weight: _asDouble(entry['weight'], 0),
              minCm: _asInt(entry['min_cm'], 0),
              maxCm: _asInt(entry['max_cm'], 0),
            ),
          );
        }
      }
    }
    final rawThresholds = yaml['dino_count'] ?? yaml['dino_count_thresholds'];
    final thresholds = <DinoCountThreshold>[];
    if (rawThresholds is List) {
      for (final entry in rawThresholds) {
        if (entry is Map) {
          thresholds.add(
            DinoCountThreshold(
              maxOdd: _asDouble(entry['max_odd'], 0),
              count: _asInt(entry['count'], 0),
            ),
          );
        }
      }
    }
    return FieldSurveyConfig(
      skillId: yaml['skill_id'] as String? ?? 'field_survey',
      mainParams: FieldSurveyMainParams.fromYaml(main),
      levelModifiers: LevelModifierEntry.mapFromYaml(yaml['level_modifiers']),
      weatherTimeModifiers: ambientModifiersFromYaml(
        yaml['weather_time_modifiers'],
      ),
      weatherTypeModifiers: ambientModifiersFromYaml(
        yaml['weather_type_modifiers'],
      ),
      client: FieldSurveyClientConfig.fromYaml(
        GameConfig._asMap(yaml['client']),
      ),
      dinoCount: thresholds,
      fossilCount: _asIntDoubleMap(
        yaml['fossil_count'] ?? yaml['card_count_weights'],
      ),
      depthWeights: buckets,
      completenessWeights: _asStringDoubleMap(yaml['completeness_weights']),
      qualityWeights: _asStringDoubleMap(yaml['quality_weights']),
      oddNoise: FossilOddNoiseConfig.fromYaml(yaml['odd_noise']),
      accuracyNoise: AccuracyNoiseConfig.fromYaml(yaml['accuracy_noise']),
      defaults: FossilGenerationDefaults.fromYaml(yaml['defaults']),
    );
  }
}

class FieldSurveyMainParams {
  const FieldSurveyMainParams({
    required this.visibilityDistanceM,
    required this.discoveryChance,
    required this.maxDiscoverySpeedKmh,
    required this.siteDiscoveryXp,
    required this.firstDiscoveryXp,
    required this.active100mXp,
    required this.passiveKmXp,
    required this.dinoAccuracy,
    required this.fossilAccuracy,
    required this.completenessAccuracy,
    required this.qualityAccuracy,
    required this.depthAccuracy,
    required this.rivalDiscovery,
    required this.siteVisibilityM,
    required this.successfulSiteDisguiseXp,
    required this.siteExplorationXp,
    required this.siteDocumentationXp,
    required this.firstDocumentationXp,
    required this.siteIdentificationXp,
  });

  final double visibilityDistanceM;
  final double discoveryChance;
  final double maxDiscoverySpeedKmh;
  final double siteDiscoveryXp;
  final double firstDiscoveryXp;
  final double active100mXp;
  final double passiveKmXp;
  final double dinoAccuracy;
  final double fossilAccuracy;
  final double completenessAccuracy;
  final double qualityAccuracy;
  final double depthAccuracy;
  final double rivalDiscovery;
  final double siteVisibilityM;
  final double successfulSiteDisguiseXp;
  final double siteExplorationXp;
  final double siteDocumentationXp;
  final double firstDocumentationXp;
  final double siteIdentificationXp;

  factory FieldSurveyMainParams.fromYaml(Map<String, dynamic> yaml) {
    return FieldSurveyMainParams(
      visibilityDistanceM: _asDouble(
        yaml['visibility_distance_m'] ?? yaml['max_distance_m'],
        20.0,
      ),
      discoveryChance: _asDouble(yaml['discovery_chance'], 0.1),
      maxDiscoverySpeedKmh: _asDouble(yaml['max_discovery_speed_kmh'], 10.0),
      siteDiscoveryXp: _asDouble(yaml['site_discovery_xp'], 20.0),
      firstDiscoveryXp: _asDouble(yaml['first_discovery_xp'], 20.0),
      active100mXp: _asDouble(yaml['active_100m_xp'], 20.0),
      passiveKmXp: _asDouble(yaml['passive_km_xp'], 100.0),
      dinoAccuracy: _asDouble(yaml['dino_accuracy'], 0.01),
      fossilAccuracy: _asDouble(yaml['fossil_accuracy'], 0.01),
      completenessAccuracy: _asDouble(yaml['completeness_accuracy'], 0.01),
      qualityAccuracy: _asDouble(yaml['quality_accuracy'], 0.01),
      depthAccuracy: _asDouble(yaml['depth_accuracy'], 0.01),
      rivalDiscovery: _asDouble(yaml['rival_discovery'], 1),
      siteVisibilityM: _asDouble(yaml['site_visibility_m'], 50),
      successfulSiteDisguiseXp: _asDouble(
        yaml['successful_site_disguise_xp'],
        40,
      ),
      siteExplorationXp: _asDouble(yaml['site_exploration_xp'], 20),
      siteDocumentationXp: _asDouble(yaml['site_documentation_xp'], 80),
      firstDocumentationXp: _asDouble(yaml['first_documentation_xp'], 20),
      siteIdentificationXp: _asDouble(yaml['site_identification_xp'], 40),
    );
  }
}

class LevelModifierEntry {
  const LevelModifierEntry({
    required this.level,
    required this.op,
    required this.value,
  });

  final int level;
  final String op;
  final double value;

  static Map<String, List<LevelModifierEntry>> mapFromYaml(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<LevelModifierEntry>>{};
    for (final entry in raw.entries) {
      final list = <LevelModifierEntry>[];
      if (entry.value is List) {
        for (final item in entry.value as List) {
          if (item is Map) {
            list.add(
              LevelModifierEntry(
                level: _asInt(item['level'], 1),
                op: item['op'] as String? ?? 'add',
                value: _asDouble(item['value'], 0),
              ),
            );
          }
        }
      }
      out[entry.key.toString()] = list;
    }
    return out;
  }
}

class ParamModifier {
  const ParamModifier({required this.op, required this.value});

  final String op;
  final double value;

  factory ParamModifier.fromYaml(Map<String, dynamic> yaml) {
    return ParamModifier(
      op: yaml['op'] as String? ?? 'replace',
      value: _asDouble(yaml['value'], 0),
    );
  }
}

/// Parse ambient modifiers: param → key (period or weather type) → mods.
Map<String, Map<String, List<ParamModifier>>> ambientModifiersFromYaml(
  Object? raw,
) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, List<ParamModifier>>>{};
  for (final paramEntry in raw.entries) {
    final keyed = <String, List<ParamModifier>>{};
    final keyedRaw = paramEntry.value;
    if (keyedRaw is Map) {
      for (final keyEntry in keyedRaw.entries) {
        final list = <ParamModifier>[];
        if (keyEntry.value is List) {
          for (final item in keyEntry.value as List) {
            if (item is Map) {
              list.add(ParamModifier.fromYaml(Map<String, dynamic>.from(item)));
            }
          }
        }
        var key = keyEntry.key.toString();
        if (key == 'sunny') key = 'clear';
        keyed[key] = list;
      }
    }
    out[paramEntry.key.toString()] = keyed;
  }
  return out;
}

/// Back-compat alias.
Map<String, Map<String, List<ParamModifier>>> weatherTimeModifiersFromYaml(
  Object? raw,
) => ambientModifiersFromYaml(raw);

class ModifiesMainParams {
  const ModifiesMainParams({this.owning = const {}, this.using = const {}});

  /// Passiveive: skill_id → param → modifier, while owned.
  final Map<String, Map<String, ParamModifier>> owning;

  /// Active: skill_id → param → modifier, while tool session is in use.
  final Map<String, Map<String, ParamModifier>> using;

  bool get hasAny => owning.isNotEmpty || using.isNotEmpty;

  bool affectsSkill(String skillId) =>
      owning.containsKey(skillId) || using.containsKey(skillId);

  Map<String, ParamModifier> paramsFor(String when, String skillId) {
    final bucket = when == 'owning' ? owning : using;
    return bucket[skillId] ?? const {};
  }

  static bool _looksLikeParamModifier(Object? value) {
    if (value is! Map) return false;
    return value.containsKey('op') && value.containsKey('value');
  }

  static bool _looksLikeParamMap(Object? value) {
    if (value is! Map) return false;
    if (value.isEmpty) return true;
    return value.values.every(_looksLikeParamModifier);
  }

  static Map<String, ParamModifier> _parseParamMap(Object? raw) {
    final map = GameConfig._asMap(raw);
    final out = <String, ParamModifier>{};
    for (final entry in map.entries) {
      if (entry.value is Map) {
        out[entry.key] = ParamModifier.fromYaml(GameConfig._asMap(entry.value));
      }
    }
    return out;
  }

  static Map<String, Map<String, ParamModifier>> _parseSkillMap(Object? raw) {
    final map = GameConfig._asMap(raw);
    final out = <String, Map<String, ParamModifier>>{};
    for (final entry in map.entries) {
      out[entry.key] = _parseParamMap(entry.value);
    }
    return out;
  }

  factory ModifiesMainParams.fromYaml(Map<String, dynamic> yaml) {
    final skill = yaml['skill'] as String?;
    Object? owningRaw = yaml['owning'];
    Object? usingRaw = yaml['using'];

    // Legacy: when + params
    if (owningRaw == null && usingRaw == null && yaml['params'] != null) {
      final whenRaw =
          (yaml['when'] as String?)?.trim().toLowerCase() ?? 'using';
      if (whenRaw == 'owning') {
        owningRaw = yaml['params'];
      } else {
        usingRaw = yaml['params'];
      }
    }

    // Single-skill shorthand: owning/using are param maps.
    if (skill != null) {
      if (_looksLikeParamMap(owningRaw)) {
        owningRaw = {skill: owningRaw};
      }
      if (_looksLikeParamMap(usingRaw)) {
        usingRaw = {skill: usingRaw};
      }
    }

    return ModifiesMainParams(
      owning: _parseSkillMap(owningRaw),
      using: _parseSkillMap(usingRaw),
    );
  }
}

class SkillStubConfig {
  const SkillStubConfig({
    required this.skillId,
    required this.enabled,
    required this.mainParams,
    required this.levelModifiers,
    this.weatherTimeModifiers = const {},
    this.weatherTypeModifiers = const {},
  });

  final String skillId;
  final bool enabled;
  final Map<String, dynamic> mainParams;
  final Map<String, List<LevelModifierEntry>> levelModifiers;
  final Map<String, Map<String, List<ParamModifier>>> weatherTimeModifiers;
  final Map<String, Map<String, List<ParamModifier>>> weatherTypeModifiers;

  bool get hasMainParams => mainParams.isNotEmpty;

  factory SkillStubConfig.fromYaml(Map<String, dynamic> yaml) {
    return SkillStubConfig(
      skillId: yaml['skill_id'] as String? ?? '',
      enabled: yaml['enabled'] == true,
      mainParams: GameConfig._asMap(yaml['main_params']),
      levelModifiers: LevelModifierEntry.mapFromYaml(yaml['level_modifiers']),
      weatherTimeModifiers: ambientModifiersFromYaml(
        yaml['weather_time_modifiers'],
      ),
      weatherTypeModifiers: ambientModifiersFromYaml(
        yaml['weather_type_modifiers'],
      ),
    );
  }
}

class FieldSurveyClientConfig {
  const FieldSurveyClientConfig({
    required this.autoDiscoverRadiusM,
    required this.cacheRadiusKm,
    required this.cacheRefreshMoveThresholdM,
    required this.discoverFailRetryS,
    required this.discoveryRerollIntervalS,
  });

  final double autoDiscoverRadiusM;
  final double cacheRadiusKm;
  final double cacheRefreshMoveThresholdM;
  final int discoverFailRetryS;
  final int discoveryRerollIntervalS;

  factory FieldSurveyClientConfig.fromYaml(Map<String, dynamic> yaml) {
    return FieldSurveyClientConfig(
      autoDiscoverRadiusM: _asDouble(yaml['auto_discover_radius_m'], 20.0),
      cacheRadiusKm: _asDouble(yaml['cache_radius_km'], 1.0),
      cacheRefreshMoveThresholdM: _asDouble(
        yaml['cache_refresh_move_threshold_m'],
        500.0,
      ),
      discoverFailRetryS: _asInt(yaml['discover_fail_retry_s'], 20),
      discoveryRerollIntervalS: _asInt(yaml['discovery_reroll_interval_s'], 10),
    );
  }
}

class FossilGenerationDefaults {
  const FossilGenerationDefaults({
    required this.subcategory,
    required this.completeness,
    required this.quality,
  });

  final String subcategory;
  final String completeness;
  final String quality;

  static const FossilGenerationDefaults fallback = FossilGenerationDefaults(
    subcategory: 'teeth',
    completeness: 'fragmentary',
    quality: 'moderate',
  );

  factory FossilGenerationDefaults.fromYaml(Object? raw) {
    if (raw is! Map) return FossilGenerationDefaults.fallback;
    return FossilGenerationDefaults(
      subcategory: raw['subcategory'] as String? ?? fallback.subcategory,
      completeness: raw['completeness'] as String? ?? fallback.completeness,
      quality: raw['quality'] as String? ?? fallback.quality,
    );
  }
}

/// Back-compat aliases for call sites during migration.
typedef SiteDiscoveryConfig = FieldSurveyConfig;
typedef SiteStewardshipConfig = FieldSurveyConfig;
typedef FossilGenerationConfig = FieldSurveyConfig;
typedef SiteDiscoveryClientConfig = FieldSurveyClientConfig;
typedef SiteDiscoveryMainParams = FieldSurveyMainParams;
typedef SiteStewardshipMainParams = FieldSurveyMainParams;

class FossilOddNoiseConfig {
  const FossilOddNoiseConfig({
    required this.dinoCount,
    required this.fossilCount,
    required this.completeness,
    required this.quality,
    required this.depth,
  });

  final double dinoCount;
  final double fossilCount;
  final double completeness;
  final double quality;
  final double depth;

  factory FossilOddNoiseConfig.fromYaml(Object? raw) {
    if (raw is Map) {
      return FossilOddNoiseConfig(
        dinoCount: _asDouble(raw['dino_count'], 0.3),
        fossilCount: _asDouble(raw['fossil_count'], 0.3),
        completeness: _asDouble(raw['completeness'], 0.3),
        quality: _asDouble(raw['quality'], 0.3),
        depth: _asDouble(raw['depth'], 0.3),
      );
    }
    // Legacy scalar odd_noise: apply the same value to every sampler.
    final shared = _asDouble(raw, 0.3);
    return FossilOddNoiseConfig(
      dinoCount: shared,
      fossilCount: shared,
      completeness: shared,
      quality: shared,
      depth: shared,
    );
  }
}

/// Per-axis jitter around skill baseline accuracy (display-only; not a main_param).
class AccuracyNoiseConfig {
  const AccuracyNoiseConfig({required this.maxDelta});

  /// Absolute half-amplitude (± accuracy points on [0, 1]), independent of baseline.
  final double maxDelta;

  static const AccuracyNoiseConfig defaults = AccuracyNoiseConfig(
    maxDelta: 0.30,
  );

  factory AccuracyNoiseConfig.fromYaml(Object? raw) {
    if (raw is! Map) return AccuracyNoiseConfig.defaults;
    return AccuracyNoiseConfig(
      maxDelta: _asDouble(raw['max_delta'], defaults.maxDelta),
    );
  }
}

class DinoCountThreshold {
  const DinoCountThreshold({required this.maxOdd, required this.count});

  final double maxOdd;
  final int count;
}

class FossilDepthBucket {
  const FossilDepthBucket({
    required this.weight,
    required this.minCm,
    required this.maxCm,
  });

  final double weight;
  final int minCm;
  final int maxCm;
}

class ToolActionsConfig {
  const ToolActionsConfig({
    required this.aerialRecon,
    required this.aerialScout,
    required this.geoCompass,
    required this.proximityScanner,
    required this.siteNavigator,
    required this.orbitSurvey,
    required this.formationMap,
    required this.terrainEcho,
    required this.ridgeGlass,
    required this.trailStriders,
    required this.expeditionDrivetrain,
    required this.canyonThrottle,
    required this.overlandChassis,
    required this.nocturneLens,
    required this.brushScrim,
    required this.blackoutCover,
  });

  final AerialActionConfig aerialRecon;
  final AerialActionConfig aerialScout;
  final GuidanceActionConfig geoCompass;
  final GuidanceActionConfig proximityScanner;
  final GuidanceActionConfig siteNavigator;
  final OrbitSurveyActionConfig orbitSurvey;
  final FormationMapActionConfig formationMap;
  final TerrainEchoActionConfig terrainEcho;
  final MainParamBuffActionConfig ridgeGlass;
  final MainParamBuffActionConfig trailStriders;
  final MainParamBuffActionConfig expeditionDrivetrain;
  final MainParamBuffActionConfig canyonThrottle;
  final MainParamBuffActionConfig overlandChassis;
  final MainParamBuffActionConfig nocturneLens;
  final DisguiseActionConfig brushScrim;
  final DisguiseActionConfig blackoutCover;

  AerialActionConfig configFor(String actionKey) {
    switch (actionKey) {
      case 'aerial_scout':
        return aerialScout;
      case 'aerial_recon':
      default:
        return aerialRecon;
    }
  }

  GuidanceActionConfig guidanceConfigFor(String actionKey) {
    switch (actionKey) {
      case 'proximity_scanner':
        return proximityScanner;
      case 'site_navigator':
        return siteNavigator;
      case 'geo_compass':
      default:
        return geoCompass;
    }
  }

  DisguiseActionConfig disguiseConfigFor(String actionKey) {
    switch (actionKey) {
      case 'blackout_cover':
        return blackoutCover;
      case 'brush_scrim':
      default:
        return brushScrim;
    }
  }

  MainParamBuffActionConfig mainParamBuffConfigFor(String actionKey) {
    switch (actionKey) {
      case 'trail_striders':
        return trailStriders;
      case 'expedition_drivetrain':
        return expeditionDrivetrain;
      case 'canyon_throttle':
        return canyonThrottle;
      case 'overland_chassis':
        return overlandChassis;
      case 'nocturne_lens':
        return nocturneLens;
      case 'ridge_glass':
      default:
        return ridgeGlass;
    }
  }

  /// YAML / game-config defaults keyed like API `params` / `base_params`.
  Map<String, dynamic> defaultsForToolName(String name) {
    switch (name) {
      case 'Aerial Recon':
        return aerialRecon.toParamsJson();
      case 'Aerial Scout':
        return aerialScout.toParamsJson();
      case 'Geo Compass':
        return geoCompass.toParamsJson(actionKey: 'geo_compass');
      case 'Proximity Scanner':
        return proximityScanner.toParamsJson(actionKey: 'proximity_scanner');
      case 'Site Navigator':
        return siteNavigator.toParamsJson(actionKey: 'site_navigator');
      case 'Orbit Survey':
        return orbitSurvey.toParamsJson();
      case 'Formation Map':
        return formationMap.toParamsJson();
      case 'Terrain Echo':
        return terrainEcho.toParamsJson();
      case 'Ridge Glass':
        return ridgeGlass.toParamsJson();
      case 'Trail Striders':
        return trailStriders.toParamsJson();
      case 'Expedition Drivetrain':
        return expeditionDrivetrain.toParamsJson();
      case 'Canyon Throttle':
        return canyonThrottle.toParamsJson();
      case 'Overland Chassis':
        return overlandChassis.toParamsJson();
      case 'Nocturne Lens':
        return nocturneLens.toParamsJson();
      case 'Brush Scrim':
        return brushScrim.toParamsJson();
      case 'Blackout Cover':
        return blackoutCover.toParamsJson();
      default:
        return const {};
    }
  }

  factory ToolActionsConfig.fromYaml(Map<String, dynamic> yaml) {
    return ToolActionsConfig(
      aerialRecon: AerialActionConfig.fromYaml(
        GameConfig._asMap(yaml['aerial_recon']),
      ),
      aerialScout: AerialActionConfig.fromYaml(
        GameConfig._asMap(yaml['aerial_scout']),
        defaults: const AerialActionConfig(
          durationMinutes: 10,
          loopEndpointToleranceM: 75.0,
          flightSpeedKmh: 35.0,
          flightDiscoveryChance: 0.008,
          flightDiscoveryDistanceM: 50.0,
          ensureTimeoutS: 600,
          shortRouteWarnFraction: 0.7,
          statsExplanation:
              'Duration is this card\'s lifetime battery. Remaining time caps how far '
              'you can draw (speed × remaining). Flight time is drawn length ÷ speed. '
              'Sites within flight discovery distance are rolled at the listed chance.',
        ),
      ),
      geoCompass: GuidanceActionConfig.fromYaml(
        GameConfig._asMap(yaml['geo_compass']),
        defaults: GuidanceActionConfig(
          durationMinutes: 15,
          exactness: 0.0,
          modifiesMainParams: const ModifiesMainParams(
            using: {
              'field_survey': {
                'discovery_chance': ParamModifier(op: 'replace', value: 0.9),
              },
            },
          ),
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation:
              'Shows a direction range toward the nearest undiscovered site; '
              'lower exactness widens the glow.',
        ),
      ),
      proximityScanner: GuidanceActionConfig.fromYaml(
        GameConfig._asMap(yaml['proximity_scanner']),
        defaults: const GuidanceActionConfig(
          durationMinutes: 15,
          exactness: 0.0,
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation:
              'Shows distance to the nearest undiscovered site as meter bands.',
        ),
      ),
      siteNavigator: GuidanceActionConfig.fromYaml(
        GameConfig._asMap(yaml['site_navigator']),
        defaults: GuidanceActionConfig(
          durationMinutes: 15,
          directionExactness: 0.0,
          distanceExactness: 0.0,
          modifiesMainParams: const ModifiesMainParams(
            using: {
              'field_survey': {
                'discovery_chance': ParamModifier(op: 'replace', value: 0.9),
              },
            },
          ),
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation:
              'Combines a direction-range glow and distance bands for the '
              'nearest undiscovered site.',
        ),
      ),
      orbitSurvey: OrbitSurveyActionConfig.fromYaml(
        GameConfig._asMap(yaml['orbit_survey']),
      ),
      formationMap: FormationMapActionConfig.fromYaml(
        GameConfig._asMap(yaml['formation_map']),
      ),
      terrainEcho: TerrainEchoActionConfig.fromYaml(
        GameConfig._asMap(yaml['terrain_echo']),
      ),
      ridgeGlass: MainParamBuffActionConfig.fromYaml(
        GameConfig._asMap(yaml['ridge_glass']),
      ),
      trailStriders: MainParamBuffActionConfig.fromYaml(
        GameConfig._asMap(yaml['trail_striders']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'site_visibility_m': ParamModifier(op: 'multiply', value: 0.95),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 100% so a fast jog '
              'still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 5%.',
        ),
      ),
      expeditionDrivetrain: MainParamBuffActionConfig.fromYaml(
        GameConfig._asMap(yaml['expedition_drivetrain']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'site_visibility_m': ParamModifier(op: 'multiply', value: 0.9),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 200% so bicycle '
              'travel still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 10%.',
        ),
      ),
      canyonThrottle: MainParamBuffActionConfig.fromYaml(
        GameConfig._asMap(yaml['canyon_throttle']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'site_visibility_m': ParamModifier(op: 'multiply', value: 0.85),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 300% so motorcycle '
              'travel still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 15%.',
        ),
      ),
      overlandChassis: MainParamBuffActionConfig.fromYaml(
        GameConfig._asMap(yaml['overland_chassis']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'site_visibility_m': ParamModifier(op: 'multiply', value: 0.8),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 400% so 4x4 travel '
              'still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 20%.',
        ),
      ),
      nocturneLens: MainParamBuffActionConfig.fromYaml(
        GameConfig._asMap(yaml['nocturne_lens']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          activeWeatherTimes: ['night'],
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'visibility_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 1.4,
                ),
                'discovery_chance': ParamModifier(op: 'multiply', value: 1.4),
              },
            },
          ),
          statsExplanation:
              'Lifetime battery; only starts and runs at night. Boosts '
              'visibility range and walk-in discovery chance by 40%.',
        ),
      ),
      brushScrim: DisguiseActionConfig.fromYaml(
        GameConfig._asMap(yaml['brush_scrim']),
        defaults: const DisguiseActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'rival_discovery': ParamModifier(op: 'multiply', value: 0),
              },
            },
          ),
          statsExplanation:
              'Covers one discovered site; multiplies rival_discovery by 0. '
              'Successful site disguise XP only when a rival would have '
              'discovered the site without the cover.',
        ),
      ),
      blackoutCover: DisguiseActionConfig.fromYaml(
        GameConfig._asMap(yaml['blackout_cover']),
        defaults: const DisguiseActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'rival_discovery': ParamModifier(op: 'multiply', value: 0.5),
              },
            },
          ),
          statsExplanation:
              'Covers one discovered site; multiplies rival_discovery by 0.5. '
              'Successful site disguise XP only when a rival would have '
              'discovered the site without the cover but the cover stops them.',
        ),
      ),
    );
  }
}

class LevelingConfig {
  const LevelingConfig({required this.skills, required this.careerTitles});

  final List<LevelingSkillConfig> skills;
  final List<String> careerTitles;

  factory LevelingConfig.fromYaml(Map<String, dynamic> yaml) {
    return LevelingConfig(
      skills: LevelingSkillConfig.listFromYaml(yaml['skills']),
      careerTitles: _asStringList(yaml['career_titles']),
    );
  }
}

class LevelingSkillConfig {
  const LevelingSkillConfig({required this.id, required this.name});

  final String id;
  final String name;

  static List<LevelingSkillConfig> listFromYaml(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => LevelingSkillConfig.fromYaml(GameConfig._asMap(item)))
        .toList();
  }

  factory LevelingSkillConfig.fromYaml(Map<String, dynamic> yaml) {
    return LevelingSkillConfig(
      id: yaml['id'] as String? ?? '',
      name: yaml['name'] as String? ?? '',
    );
  }
}

class GuidanceActionConfig {
  const GuidanceActionConfig({
    required this.durationMinutes,
    this.exactness,
    this.directionExactness,
    this.distanceExactness,
    this.modifiesMainParams,
    required this.directionHintPeriodS,
    required this.maxDirectionRangeDeg,
    required this.minDirectionRangeDeg,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final double? exactness;
  final double? directionExactness;
  final double? distanceExactness;
  final ModifiesMainParams? modifiesMainParams;
  final double directionHintPeriodS;
  final double maxDirectionRangeDeg;
  final double minDirectionRangeDeg;
  final String statsExplanation;

  /// Walk-in discovery chance from using/field_survey modifiers.
  double? get discoveryChance {
    final mods = modifiesMainParams;
    if (mods == null) return null;
    return (mods.paramsFor('using', 'field_survey')['discovery_chance'] ??
            mods.paramsFor('using', 'site_discovery')['discovery_chance'])
        ?.value;
  }

  double get resolvedDirectionExactness =>
      directionExactness ?? exactness ?? 0.0;

  double get resolvedDistanceExactness => distanceExactness ?? exactness ?? 0.0;

  Map<String, dynamic> toParamsJson({required String actionKey}) {
    final out = <String, dynamic>{
      'duration_minutes': durationMinutes,
      'direction_hint_period_s': directionHintPeriodS,
      'max_direction_range_deg': maxDirectionRangeDeg,
      'min_direction_range_deg': minDirectionRangeDeg,
      'stats_explanation': statsExplanation,
    };
    final mods = modifiesMainParams;
    if (mods != null && mods.hasAny) {
      Map<String, dynamic> encodeSkillMap(
        Map<String, Map<String, ParamModifier>> skillMap,
      ) => {
        for (final skill in skillMap.entries)
          skill.key: {
            for (final p in skill.value.entries)
              p.key: {'op': p.value.op, 'value': p.value.value},
          },
      };
      out['modifies_main_params'] = {
        if (mods.owning.isNotEmpty) 'owning': encodeSkillMap(mods.owning),
        if (mods.using.isNotEmpty) 'using': encodeSkillMap(mods.using),
      };
    }
    switch (actionKey) {
      case 'site_navigator':
        out['direction_exactness'] = resolvedDirectionExactness;
        out['distance_exactness'] = resolvedDistanceExactness;
        if (discoveryChance != null) {
          out['discovery_chance'] = discoveryChance;
        }
      case 'proximity_scanner':
        out['exactness'] = resolvedDistanceExactness;
      case 'geo_compass':
      default:
        out['exactness'] = resolvedDirectionExactness;
        if (discoveryChance != null) {
          out['discovery_chance'] = discoveryChance;
        }
    }
    return out;
  }

  factory GuidanceActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    GuidanceActionConfig? defaults,
  }) {
    final d =
        defaults ??
        const GuidanceActionConfig(
          durationMinutes: 15,
          exactness: 0.0,
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation: '',
        );
    ModifiesMainParams? mods = d.modifiesMainParams;
    final rawMods = yaml['modifies_main_params'];
    if (rawMods is Map) {
      mods = ModifiesMainParams.fromYaml(GameConfig._asMap(rawMods));
    } else if (yaml.containsKey('discovery_chance')) {
      // Legacy bare discovery_chance → formalize as replace modifier.
      final chance = _asOptionalDouble(yaml['discovery_chance'], null);
      if (chance != null) {
        mods = ModifiesMainParams(
          using: {
            'field_survey': {
              'discovery_chance': ParamModifier(op: 'replace', value: chance),
            },
          },
        );
      } else {
        mods = null;
      }
    }
    return GuidanceActionConfig(
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      exactness: _asOptionalDouble(yaml['exactness'], d.exactness),
      directionExactness: _asOptionalDouble(
        yaml['direction_exactness'],
        d.directionExactness,
      ),
      distanceExactness: _asOptionalDouble(
        yaml['distance_exactness'],
        d.distanceExactness,
      ),
      modifiesMainParams: mods,
      directionHintPeriodS: _asDouble(
        yaml['direction_hint_period_s'],
        d.directionHintPeriodS,
      ),
      maxDirectionRangeDeg: _asDouble(
        yaml['max_direction_range_deg'],
        d.maxDirectionRangeDeg,
      ),
      minDirectionRangeDeg: _asDouble(
        yaml['min_direction_range_deg'],
        d.minDirectionRangeDeg,
      ),
      statsExplanation: _asString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}

class PeriodRgbColors {
  const PeriodRgbColors({
    required this.cretaceous,
    required this.jurassic,
    required this.triassic,
  });

  final (int, int, int) cretaceous;
  final (int, int, int) jurassic;
  final (int, int, int) triassic;

  factory PeriodRgbColors.fromYaml(Map<String, dynamic> yaml) {
    return PeriodRgbColors(
      cretaceous: _requireRgb(yaml['cretaceous'], 'cretaceous'),
      jurassic: _requireRgb(yaml['jurassic'], 'jurassic'),
      triassic: _requireRgb(yaml['triassic'], 'triassic'),
    );
  }

  (int, int, int) forPeriod(String period) {
    switch (period.toLowerCase()) {
      case 'jurassic':
        return jurassic;
      case 'triassic':
        return triassic;
      case 'cretaceous':
      default:
        return cretaceous;
    }
  }
}

class PeriodColorsConfig {
  const PeriodColorsConfig({
    required this.siteMarkers,
    required this.orbitSurvey,
  });

  final PeriodRgbColors siteMarkers;
  final PeriodRgbColors orbitSurvey;

  factory PeriodColorsConfig.fromYaml(Map<String, dynamic> yaml) {
    return PeriodColorsConfig(
      siteMarkers: PeriodRgbColors.fromYaml(
        GameConfig._asMap(yaml['site_markers']),
      ),
      orbitSurvey: PeriodRgbColors.fromYaml(
        GameConfig._asMap(yaml['orbit_survey']),
      ),
    );
  }
}

class OrbitSurveyActionConfig {
  const OrbitSurveyActionConfig({
    required this.durationMinutes,
    required this.accuracy,
    required this.range,
    required this.minRangeM,
    required this.maxRangeM,
    required this.baseAlpha,
    required this.rangeFade,
    required this.boundaryBlur,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final double accuracy;
  final double range;
  final double minRangeM;
  final double maxRangeM;
  final double baseAlpha;
  final double rangeFade;
  final double boundaryBlur;
  final String statsExplanation;

  double get resolvedRangeM => minRangeM + range * (maxRangeM - minRangeM);

  Map<String, dynamic> toParamsJson() => {
    'duration_minutes': durationMinutes,
    'accuracy': accuracy,
    'range': range,
    'min_range_m': minRangeM,
    'max_range_m': maxRangeM,
    'base_alpha': baseAlpha,
    'range_fade': rangeFade,
    'boundary_blur': boundaryBlur,
    'stats_explanation': statsExplanation,
  };

  factory OrbitSurveyActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    OrbitSurveyActionConfig? defaults,
  }) {
    final d =
        defaults ??
        const OrbitSurveyActionConfig(
          durationMinutes: 10,
          accuracy: 0.75,
          range: 0.35,
          minRangeM: 200.0,
          maxRangeM: 2000.0,
          baseAlpha: 0.48,
          rangeFade: 0.55,
          boundaryBlur: 0.7,
          statsExplanation:
              'Colors the map by the period of the nearest undiscovered '
              'field site. Higher accuracy sharpens boundaries; higher '
              'range widens the circle (200 m–2 km).',
        );
    return OrbitSurveyActionConfig(
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      accuracy: _asDouble(yaml['accuracy'], d.accuracy).clamp(0.0, 1.0),
      range: _asDouble(yaml['range'], d.range).clamp(0.0, 1.0),
      minRangeM: _asDouble(yaml['min_range_m'], d.minRangeM),
      maxRangeM: _asDouble(yaml['max_range_m'], d.maxRangeM),
      baseAlpha: _asDouble(yaml['base_alpha'], d.baseAlpha).clamp(0.0, 1.0),
      rangeFade: _asDouble(yaml['range_fade'], d.rangeFade).clamp(0.0, 1.0),
      boundaryBlur: _asDouble(
        yaml['boundary_blur'],
        d.boundaryBlur,
      ).clamp(0.0, 1.0),
      statsExplanation: _asString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}

class TerrainEchoActionConfig {
  const TerrainEchoActionConfig({
    required this.accuracy,
    required this.rangeM,
    required this.minRangeM,
    required this.maxRangeM,
    required this.durationMinutes,
    required this.minDurationMinutes,
    required this.maxDurationMinutes,
    required this.ringIncrementM,
    required this.sweepPeriodS,
    required this.statsExplanation,
  });

  final double accuracy;
  final double rangeM;
  final double minRangeM;
  final double maxRangeM;
  final int durationMinutes;
  final int minDurationMinutes;
  final int maxDurationMinutes;
  final double ringIncrementM;
  final double sweepPeriodS;
  final String statsExplanation;

  Map<String, dynamic> toParamsJson() => {
    'accuracy': accuracy,
    'range_m': rangeM,
    'min_range_m': minRangeM,
    'max_range_m': maxRangeM,
    'duration_minutes': durationMinutes,
    'min_duration_minutes': minDurationMinutes,
    'max_duration_minutes': maxDurationMinutes,
    'ring_increment_m': ringIncrementM,
    'sweep_period_s': sweepPeriodS,
    'stats_explanation': statsExplanation,
  };

  factory TerrainEchoActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    TerrainEchoActionConfig? defaults,
  }) {
    final d =
        defaults ??
        const TerrainEchoActionConfig(
          accuracy: 0.0,
          rangeM: 20.0,
          minRangeM: 20.0,
          maxRangeM: 200.0,
          durationMinutes: 5,
          minDurationMinutes: 5,
          maxDurationMinutes: 20,
          ringIncrementM: 20.0,
          sweepPeriodS: 4.0,
          statsExplanation:
              'Rotating survey pulse around your position. Blips mark nearby '
              'sites you have not discovered yet. Higher accuracy tightens '
              'blips; range sets pulse radius (20–200 m).',
        );
    return TerrainEchoActionConfig(
      accuracy: _asDouble(yaml['accuracy'], d.accuracy).clamp(0.0, 1.0),
      rangeM: _asDouble(yaml['range_m'], d.rangeM),
      minRangeM: _asDouble(yaml['min_range_m'], d.minRangeM),
      maxRangeM: _asDouble(yaml['max_range_m'], d.maxRangeM),
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      minDurationMinutes: _asInt(
        yaml['min_duration_minutes'],
        d.minDurationMinutes,
      ),
      maxDurationMinutes: _asInt(
        yaml['max_duration_minutes'],
        d.maxDurationMinutes,
      ),
      ringIncrementM: _asDouble(yaml['ring_increment_m'], d.ringIncrementM),
      sweepPeriodS: _asDouble(yaml['sweep_period_s'], d.sweepPeriodS),
      statsExplanation: _asString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}

class MainParamBuffActionConfig {
  const MainParamBuffActionConfig({
    required this.durationMinutes,
    this.modifiesMainParams,
    this.activeWeatherTimes,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final ModifiesMainParams? modifiesMainParams;
  final List<String>? activeWeatherTimes;
  final String statsExplanation;

  double? get addedVisibilityRangeM {
    final mod = siteDiscoveryMod('visibility_distance_m');
    if (mod == null || mod.op != 'add') return null;
    return mod.value;
  }

  double? get addedDiscoveryRate {
    final mod = siteDiscoveryMod('discovery_chance');
    if (mod == null || mod.op != 'add') return null;
    return mod.value;
  }

  /// Active `using` / `field_survey` modifier for [paramKey], if any.
  ParamModifier? siteDiscoveryMod(String paramKey) {
    final mods = modifiesMainParams;
    if (mods == null) return null;
    return mods.paramsFor('using', 'field_survey')[paramKey] ??
        mods.paramsFor('using', 'site_discovery')[paramKey];
  }

  bool isActiveForWeatherTime(String? weatherTime) {
    final allowed = activeWeatherTimes;
    if (allowed == null) return true;
    if (weatherTime == null) return false;
    return allowed.contains(weatherTime);
  }

  Map<String, dynamic> toParamsJson() {
    final out = <String, dynamic>{
      'duration_minutes': durationMinutes,
      'stats_explanation': statsExplanation,
    };
    final times = activeWeatherTimes;
    if (times != null) {
      out['active_weather_times'] = List<String>.from(times);
    }
    final mods = modifiesMainParams;
    if (mods != null && mods.hasAny) {
      Map<String, dynamic> encodeSkillMap(
        Map<String, Map<String, ParamModifier>> skillMap,
      ) => {
        for (final skill in skillMap.entries)
          skill.key: {
            for (final p in skill.value.entries)
              p.key: {'op': p.value.op, 'value': p.value.value},
          },
      };
      out['modifies_main_params'] = {
        if (mods.owning.isNotEmpty) 'owning': encodeSkillMap(mods.owning),
        if (mods.using.isNotEmpty) 'using': encodeSkillMap(mods.using),
      };
    }
    return out;
  }

  factory MainParamBuffActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    MainParamBuffActionConfig? defaults,
  }) {
    final d =
        defaults ??
        const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'visibility_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 1.3,
                ),
                'discovery_chance': ParamModifier(op: 'multiply', value: 1.3),
                'max_discovery_speed_kmh': ParamModifier(
                  op: 'multiply',
                  value: 0.7,
                ),
              },
            },
          ),
          statsExplanation:
              'While active, boosts site visibility range and walk-in '
              'discovery chance, and decreases max discovery speed for all sites.',
        );
    ModifiesMainParams? mods = d.modifiesMainParams;
    final rawMods = yaml['modifies_main_params'];
    if (rawMods is Map) {
      mods = ModifiesMainParams.fromYaml(GameConfig._asMap(rawMods));
    }
    List<String>? activeTimes = d.activeWeatherTimes;
    final rawTimes = yaml['active_weather_times'];
    if (rawTimes is List) {
      activeTimes = rawTimes.map((e) => e.toString()).toList();
    }
    return MainParamBuffActionConfig(
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      modifiesMainParams: mods,
      activeWeatherTimes: activeTimes,
      statsExplanation: _asString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}

typedef RidgeGlassActionConfig = MainParamBuffActionConfig;

class DisguiseActionConfig {
  const DisguiseActionConfig({
    required this.durationMinutes,
    this.modifiesMainParams,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final ModifiesMainParams? modifiesMainParams;
  final String statsExplanation;

  ParamModifier? siteStewardshipMod(String paramKey) {
    final mods = modifiesMainParams;
    if (mods == null) return null;
    return mods.paramsFor('using', 'field_survey')[paramKey] ??
        mods.paramsFor('using', 'site_stewardship')[paramKey];
  }

  ParamModifier? get rivalDiscoveryMod => siteStewardshipMod('rival_discovery');

  Map<String, dynamic> toParamsJson() {
    final out = <String, dynamic>{
      'duration_minutes': durationMinutes,
      'stats_explanation': statsExplanation,
    };
    final mods = modifiesMainParams;
    if (mods != null && mods.hasAny) {
      Map<String, dynamic> encodeSkillMap(
        Map<String, Map<String, ParamModifier>> skillMap,
      ) => {
        for (final skill in skillMap.entries)
          skill.key: {
            for (final p in skill.value.entries)
              p.key: {'op': p.value.op, 'value': p.value.value},
          },
      };
      out['modifies_main_params'] = {
        if (mods.owning.isNotEmpty) 'owning': encodeSkillMap(mods.owning),
        if (mods.using.isNotEmpty) 'using': encodeSkillMap(mods.using),
      };
    }
    return out;
  }

  factory DisguiseActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    DisguiseActionConfig? defaults,
  }) {
    final d =
        defaults ??
        const DisguiseActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'rival_discovery': ParamModifier(op: 'multiply', value: 0.5),
              },
            },
          ),
          statsExplanation: '',
        );
    ModifiesMainParams? mods = d.modifiesMainParams;
    final rawMods = yaml['modifies_main_params'];
    if (rawMods is Map) {
      mods = ModifiesMainParams.fromYaml(GameConfig._asMap(rawMods));
    } else if (yaml.containsKey('discovery_chance_multiplier')) {
      // Legacy bare multiplier → formalize as rival_discovery multiply.
      final value = _asDouble(yaml['discovery_chance_multiplier'], 0.5);
      mods = ModifiesMainParams(
        using: {
          'field_survey': {
            'rival_discovery': ParamModifier(op: 'multiply', value: value),
          },
        },
      );
    }
    return DisguiseActionConfig(
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      modifiesMainParams: mods,
      statsExplanation: _asString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}

(int, int, int) _requireRgb(dynamic value, String key) {
  if (value is String) {
    final raw = value.trim().replaceFirst('#', '');
    if (raw.length == 6) {
      final r = int.tryParse(raw.substring(0, 2), radix: 16);
      final g = int.tryParse(raw.substring(2, 4), radix: 16);
      final b = int.tryParse(raw.substring(4, 6), radix: 16);
      if (r != null && g != null && b != null) return (r, g, b);
    }
  }
  if (value is List && value.length == 3) {
    final r = value[0] is num ? (value[0] as num).round() : null;
    final g = value[1] is num ? (value[1] as num).round() : null;
    final b = value[2] is num ? (value[2] as num).round() : null;
    if (r != null &&
        g != null &&
        b != null &&
        r >= 0 &&
        r <= 255 &&
        g >= 0 &&
        g <= 255 &&
        b >= 0 &&
        b <= 255) {
      return (r, g, b);
    }
  }
  throw FormatException('period_colors.yaml: $key must be #RRGGBB');
}

class FormationMapActionConfig {
  const FormationMapActionConfig({
    required this.durationMinutes,
    required this.accuracy,
    required this.widenessM,
    required this.minWidenessM,
    required this.maxWidenessM,
    required this.cellSizeM,
    required this.baseAlpha,
    required this.rangeFade,
    required this.boundaryBlur,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final double accuracy;
  final double widenessM;
  final double minWidenessM;
  final double maxWidenessM;
  final double cellSizeM;
  final double baseAlpha;
  final double rangeFade;
  final double boundaryBlur;
  final String statsExplanation;

  double get resolvedWidenessM {
    final cell = cellSizeM <= 0 ? 500.0 : cellSizeM;
    final lo = minWidenessM < cell ? cell : minWidenessM;
    final hi = maxWidenessM < lo ? lo : maxWidenessM;
    final raw = widenessM.clamp(lo, hi);
    final n = (raw / cell).round().clamp(1, 100);
    return n * cell;
  }

  Map<String, dynamic> toParamsJson() => {
    'duration_minutes': durationMinutes,
    'accuracy': accuracy,
    'wideness_m': widenessM,
    'min_wideness_m': minWidenessM,
    'max_wideness_m': maxWidenessM,
    'cell_size_m': cellSizeM,
    'base_alpha': baseAlpha,
    'range_fade': rangeFade,
    'boundary_blur': boundaryBlur,
    'stats_explanation': statsExplanation,
  };

  factory FormationMapActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    FormationMapActionConfig? defaults,
  }) {
    final d =
        defaults ??
        const FormationMapActionConfig(
          durationMinutes: 10,
          accuracy: 0.75,
          widenessM: 500.0,
          minWidenessM: 500.0,
          maxWidenessM: 2000.0,
          cellSizeM: 500.0,
          baseAlpha: 0.48,
          rangeFade: 0.0,
          boundaryBlur: 1.0,
          statsExplanation:
              'Colors a fixed square of the map by rock type. Higher '
              'accuracy sharpens boundaries; wideness sets the side '
              'length (500 m–2 km) on the same 500 m grid used for field '
              'sites, locked to this tool occurrence.',
        );
    return FormationMapActionConfig(
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      accuracy: _asDouble(yaml['accuracy'], d.accuracy).clamp(0.0, 1.0),
      widenessM: _asDouble(yaml['wideness_m'], d.widenessM),
      minWidenessM: _asDouble(yaml['min_wideness_m'], d.minWidenessM),
      maxWidenessM: _asDouble(yaml['max_wideness_m'], d.maxWidenessM),
      cellSizeM: _asDouble(yaml['cell_size_m'], d.cellSizeM),
      baseAlpha: _asDouble(yaml['base_alpha'], d.baseAlpha).clamp(0.0, 1.0),
      rangeFade: _asDouble(yaml['range_fade'], d.rangeFade).clamp(0.0, 1.0),
      boundaryBlur: _asDouble(
        yaml['boundary_blur'],
        d.boundaryBlur,
      ).clamp(0.0, 1.0),
      statsExplanation: _asString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}

class RockTypeColorsConfig {
  const RockTypeColorsConfig({required this.formationMap});

  final Map<String, (int, int, int)> formationMap;

  (int, int, int) forRockType(String? rockType) {
    final key = (rockType ?? '').trim().toLowerCase();
    if (key.isNotEmpty && formationMap.containsKey(key)) {
      return formationMap[key]!;
    }
    return formationMap['other'] ?? (0x88, 0x88, 0x88);
  }

  factory RockTypeColorsConfig.fromYaml(Map<String, dynamic> yaml) {
    final raw = GameConfig._asMap(yaml['formation_map']);
    final colors = <String, (int, int, int)>{};
    for (final entry in raw.entries) {
      colors[entry.key.toString().trim().toLowerCase()] = _requireRgb(
        entry.value,
        entry.key.toString(),
      );
    }
    return RockTypeColorsConfig(formationMap: colors);
  }
}

class AerialActionConfig {
  const AerialActionConfig({
    required this.durationMinutes,
    required this.loopEndpointToleranceM,
    required this.flightSpeedKmh,
    required this.flightDiscoveryChance,
    required this.flightDiscoveryDistanceM,
    required this.ensureTimeoutS,
    required this.shortRouteWarnFraction,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final double loopEndpointToleranceM;
  final double flightSpeedKmh;
  final double flightDiscoveryChance;
  final double flightDiscoveryDistanceM;
  final int ensureTimeoutS;
  final double shortRouteWarnFraction;
  final String statsExplanation;

  /// Derived draw/deploy limit: speed × duration.
  double get maxRouteKm => flightSpeedKmh * durationMinutes / 60.0;

  Map<String, dynamic> toParamsJson() => {
    'duration_minutes': durationMinutes,
    'loop_endpoint_tolerance_m': loopEndpointToleranceM,
    'flight_speed_kmh': flightSpeedKmh,
    'flight_discovery_chance': flightDiscoveryChance,
    'flight_discovery_distance_m': flightDiscoveryDistanceM,
    'ensure_timeout_s': ensureTimeoutS,
    'short_route_warn_fraction': shortRouteWarnFraction,
    'stats_explanation': statsExplanation,
  };

  factory AerialActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    AerialActionConfig? defaults,
  }) {
    final d =
        defaults ??
        const AerialActionConfig(
          durationMinutes: 60,
          loopEndpointToleranceM: 75.0,
          flightSpeedKmh: 50.0,
          flightDiscoveryChance: 0.2,
          flightDiscoveryDistanceM: 200.0,
          ensureTimeoutS: 600,
          shortRouteWarnFraction: 0.7,
          statsExplanation:
              'Duration is this card\'s lifetime battery. Remaining time caps how far '
              'you can draw (speed × remaining). Flight time is drawn length ÷ speed. '
              'Sites within flight discovery distance are rolled at the listed chance.',
        );
    return AerialActionConfig(
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      loopEndpointToleranceM: _asDouble(
        yaml['loop_endpoint_tolerance_m'],
        d.loopEndpointToleranceM,
      ),
      flightSpeedKmh: _asDouble(yaml['flight_speed_kmh'], d.flightSpeedKmh),
      flightDiscoveryChance: _asDouble(
        yaml['flight_discovery_chance'] ?? yaml['discovery_chance'],
        d.flightDiscoveryChance,
      ),
      flightDiscoveryDistanceM: _asDouble(
        yaml['flight_discovery_distance_m'] ?? yaml['discovery_distance_m'],
        d.flightDiscoveryDistanceM,
      ),
      ensureTimeoutS: _asInt(yaml['ensure_timeout_s'], d.ensureTimeoutS),
      shortRouteWarnFraction: _asDouble(
        yaml['short_route_warn_fraction'],
        d.shortRouteWarnFraction,
      ),
      statsExplanation: _asString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}

double _asDouble(dynamic value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? _asOptionalDouble(dynamic value, double? fallback) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _asInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String _asString(dynamic value, String fallback) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return fallback;
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item != null) item.toString(),
  ];
}

Map<int, double> _asIntDoubleMap(dynamic raw) {
  if (raw is! Map) return {};
  final out = <int, double>{};
  for (final entry in raw.entries) {
    final key = int.tryParse(entry.key.toString());
    if (key == null) continue;
    final value = entry.value;
    if (value is num) {
      out[key] = value.toDouble();
    }
  }
  return out;
}

Map<String, double> _asStringDoubleMap(dynamic raw) {
  if (raw is! Map) return {};
  final out = <String, double>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is num) {
      out[entry.key.toString()] = value.toDouble();
    }
  }
  return out;
}
