import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// Shared game-mechanics control board (YAML under assets/game_config/).
///
/// Source of truth lives at `backend/app/game_config/` and is linked into
/// Flutter assets. Call [GameConfig.load] once in `main()` before `runApp`.
class GameConfig {
  GameConfig({
    required this.siteGeneration,
    required this.siteDiscovery,
    required this.fossilGeneration,
    required this.fossilDiscovery,
    required this.fossilExcavation,
    required this.toolActions,
    required this.periodColors,
    required this.rockTypeColors,
    required this.leveling,
  });

  final SiteGenerationConfig siteGeneration;
  final SiteDiscoveryConfig siteDiscovery;
  final FossilGenerationConfig fossilGeneration;
  final FossilDiscoveryConfig fossilDiscovery;
  final FossilExcavationConfig fossilExcavation;
  final ToolActionsConfig toolActions;
  final PeriodColorsConfig periodColors;
  final RockTypeColorsConfig rockTypeColors;
  final LevelingConfig leveling;

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
      siteDiscoveryYaml: await read('site_discovery.yaml'),
      fossilGenerationYaml: await read('fossil_generation.yaml'),
      fossilDiscoveryYaml: await read('fossil_discovery.yaml'),
      fossilExcavationYaml: await read('fossil_excavation.yaml'),
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
    required String siteDiscoveryYaml,
    required String fossilGenerationYaml,
    required String fossilDiscoveryYaml,
    required String fossilExcavationYaml,
    required String toolActionsYaml,
    required String periodColorsYaml,
    required String rockTypeColorsYaml,
    required String levelingYaml,
  }) {
    final config = GameConfig(
      siteGeneration: SiteGenerationConfig.fromYaml(
        _asMap(loadYaml(siteGenerationYaml)),
      ),
      siteDiscovery: SiteDiscoveryConfig.fromYaml(
        _asMap(loadYaml(siteDiscoveryYaml)),
      ),
      fossilGeneration: FossilGenerationConfig.fromYaml(
        _asMap(loadYaml(fossilGenerationYaml)),
      ),
      fossilDiscovery: FossilDiscoveryConfig.fromYaml(
        _asMap(loadYaml(fossilDiscoveryYaml)),
      ),
      fossilExcavation: FossilExcavationConfig.fromYaml(
        _asMap(loadYaml(fossilExcavationYaml)),
      ),
      toolActions: ToolActionsConfig.fromYaml(
        _asMap(loadYaml(toolActionsYaml)),
      ),
      periodColors: PeriodColorsConfig.fromYaml(
        _asMap(loadYaml(periodColorsYaml)),
      ),
      rockTypeColors: RockTypeColorsConfig.fromYaml(
        _asMap(loadYaml(rockTypeColorsYaml)),
      ),
      leveling: LevelingConfig.fromYaml(
        _asMap(loadYaml(levelingYaml)),
      ),
    );
    _instance = config;
    return config;
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
  const SiteGenerationConfig({
    required this.cellSizeM,
    required this.client,
  });

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
  const SiteGenerationClientConfig({
    required this.nearbyRadiusKm,
  });

  final double nearbyRadiusKm;

  factory SiteGenerationClientConfig.fromYaml(Map<String, dynamic> yaml) {
    return SiteGenerationClientConfig(
      nearbyRadiusKm: _asDouble(yaml['nearby_radius_km'], 1.0),
    );
  }
}

class SiteDiscoveryConfig {
  const SiteDiscoveryConfig({
    required this.maxDistanceM,
    required this.discoveryChance,
    required this.client,
  });

  final double maxDistanceM;
  final double discoveryChance;
  final SiteDiscoveryClientConfig client;

  factory SiteDiscoveryConfig.fromYaml(Map<String, dynamic> yaml) {
    return SiteDiscoveryConfig(
      maxDistanceM: _asDouble(yaml['max_distance_m'], 50.0),
      discoveryChance: _asDouble(yaml['discovery_chance'], 0.3),
      client: SiteDiscoveryClientConfig.fromYaml(
        GameConfig._asMap(yaml['client']),
      ),
    );
  }
}

class SiteDiscoveryClientConfig {
  const SiteDiscoveryClientConfig({
    required this.autoDiscoverRadiusM,
    required this.cacheRadiusKm,
    required this.cacheRefreshMoveThresholdM,
    required this.discoverFailRetryS,
  });

  final double autoDiscoverRadiusM;
  final double cacheRadiusKm;
  final double cacheRefreshMoveThresholdM;
  final int discoverFailRetryS;

  factory SiteDiscoveryClientConfig.fromYaml(Map<String, dynamic> yaml) {
    return SiteDiscoveryClientConfig(
      autoDiscoverRadiusM: _asDouble(yaml['auto_discover_radius_m'], 50.0),
      cacheRadiusKm: _asDouble(yaml['cache_radius_km'], 1.0),
      cacheRefreshMoveThresholdM: _asDouble(
        yaml['cache_refresh_move_threshold_m'],
        500.0,
      ),
      discoverFailRetryS: _asInt(yaml['discover_fail_retry_s'], 20),
    );
  }
}

class FossilGenerationConfig {
  const FossilGenerationConfig({
    required this.oddNoise,
    required this.dinoCountThresholds,
    required this.cardCountWeights,
    required this.depthBuckets,
  });

  final FossilOddNoiseConfig oddNoise;
  final List<DinoCountThreshold> dinoCountThresholds;
  final Map<int, double> cardCountWeights;
  final List<FossilDepthBucket> depthBuckets;

  factory FossilGenerationConfig.fromYaml(Map<String, dynamic> yaml) {
    final rawBuckets = yaml['depth_buckets'];
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
    final rawThresholds = yaml['dino_count_thresholds'];
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
    return FossilGenerationConfig(
      oddNoise: FossilOddNoiseConfig.fromYaml(yaml['odd_noise']),
      dinoCountThresholds: thresholds,
      cardCountWeights: _asIntDoubleMap(yaml['card_count_weights']),
      depthBuckets: buckets,
    );
  }
}

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

class DinoCountThreshold {
  const DinoCountThreshold({
    required this.maxOdd,
    required this.count,
  });

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

class FossilDiscoveryConfig {
  const FossilDiscoveryConfig({required this.enabled});

  final bool enabled;

  factory FossilDiscoveryConfig.fromYaml(Map<String, dynamic> yaml) {
    return FossilDiscoveryConfig(enabled: yaml['enabled'] == true);
  }
}

class FossilExcavationConfig {
  const FossilExcavationConfig({required this.enabled});

  final bool enabled;

  factory FossilExcavationConfig.fromYaml(Map<String, dynamic> yaml) {
    return FossilExcavationConfig(enabled: yaml['enabled'] == true);
  }
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
  });

  final AerialMissionActionConfig aerialRecon;
  final AerialMissionActionConfig aerialScout;
  final GuidanceActionConfig geoCompass;
  final GuidanceActionConfig proximityScanner;
  final GuidanceActionConfig siteNavigator;
  final OrbitSurveyActionConfig orbitSurvey;
  final FormationMapActionConfig formationMap;
  final TerrainEchoActionConfig terrainEcho;

  AerialMissionActionConfig configFor(String actionKey) {
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
      default:
        return const {};
    }
  }

  factory ToolActionsConfig.fromYaml(Map<String, dynamic> yaml) {
    return ToolActionsConfig(
      aerialRecon: AerialMissionActionConfig.fromYaml(
        GameConfig._asMap(yaml['aerial_recon']),
      ),
      aerialScout: AerialMissionActionConfig.fromYaml(
        GameConfig._asMap(yaml['aerial_scout']),
        defaults: const AerialMissionActionConfig(
          durationMinutes: 10,
          loopEndpointToleranceM: 75.0,
          flightSpeedKmh: 35.0,
          discoveryChance: 0.008,
          discoveryDistanceM: 120.0,
          ensureTimeoutS: 600,
          shortRouteWarnFraction: 0.7,
          statsExplanation:
              'Duration caps how far you can draw (speed × duration). Flight time is '
              'drawn length ÷ speed. Sites within discovery distance are rolled at the '
              'listed chance.',
        ),
      ),
      geoCompass: GuidanceActionConfig.fromYaml(
        GameConfig._asMap(yaml['geo_compass']),
        defaults: const GuidanceActionConfig(
          durationMinutes: 15,
          exactness: 0.0,
          discoveryChance: 0.9,
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
          discoveryChance: null,
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation:
              'Shows distance to the nearest undiscovered site as meter bands.',
        ),
      ),
      siteNavigator: GuidanceActionConfig.fromYaml(
        GameConfig._asMap(yaml['site_navigator']),
        defaults: const GuidanceActionConfig(
          durationMinutes: 15,
          directionExactness: 0.0,
          distanceExactness: 0.0,
          discoveryChance: 0.9,
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
    );
  }
}

class LevelingConfig {
  const LevelingConfig({
    required this.skills,
    required this.rewards,
    required this.careerTitles,
  });

  final List<LevelingSkillConfig> skills;
  final LevelingRewardsConfig rewards;
  final List<String> careerTitles;

  factory LevelingConfig.fromYaml(Map<String, dynamic> yaml) {
    return LevelingConfig(
      skills: LevelingSkillConfig.listFromYaml(yaml['skills']),
      rewards: LevelingRewardsConfig.fromYaml(
        GameConfig._asMap(yaml['rewards']),
      ),
      careerTitles: _asStringList(yaml['career_titles']),
    );
  }
}

class LevelingSkillConfig {
  const LevelingSkillConfig({
    required this.id,
    required this.name,
  });

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

class LevelingRewardsConfig {
  const LevelingRewardsConfig({
    required this.siteDiscoverSiteDiscoveryXp,
    required this.fossilDiscoverFossilDetectionXp,
    required this.activeKmSiteDiscoveryXp,
    required this.passiveKmSiteDiscoveryXp,
  });

  final int siteDiscoverSiteDiscoveryXp;
  final int fossilDiscoverFossilDetectionXp;
  final int activeKmSiteDiscoveryXp;
  final int passiveKmSiteDiscoveryXp;

  factory LevelingRewardsConfig.fromYaml(Map<String, dynamic> yaml) {
    return LevelingRewardsConfig(
      siteDiscoverSiteDiscoveryXp:
          _asInt(yaml['site_discover_site_discovery_xp'], 10),
      fossilDiscoverFossilDetectionXp:
          _asInt(yaml['fossil_discover_fossil_detection_xp'], 5),
      activeKmSiteDiscoveryXp: _asInt(yaml['active_km_site_discovery_xp'], 30),
      passiveKmSiteDiscoveryXp:
          _asInt(yaml['passive_km_site_discovery_xp'], 5),
    );
  }
}

class GuidanceActionConfig {
  const GuidanceActionConfig({
    required this.durationMinutes,
    this.exactness,
    this.directionExactness,
    this.distanceExactness,
    this.discoveryChance,
    required this.directionHintPeriodS,
    required this.maxDirectionRangeDeg,
    required this.minDirectionRangeDeg,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final double? exactness;
  final double? directionExactness;
  final double? distanceExactness;
  final double? discoveryChance;
  final double directionHintPeriodS;
  final double maxDirectionRangeDeg;
  final double minDirectionRangeDeg;
  final String statsExplanation;

  double get resolvedDirectionExactness =>
      directionExactness ?? exactness ?? 0.0;

  double get resolvedDistanceExactness =>
      distanceExactness ?? exactness ?? 0.0;

  Map<String, dynamic> toParamsJson({required String actionKey}) {
    final out = <String, dynamic>{
      'duration_minutes': durationMinutes,
      'direction_hint_period_s': directionHintPeriodS,
      'max_direction_range_deg': maxDirectionRangeDeg,
      'min_direction_range_deg': minDirectionRangeDeg,
      'stats_explanation': statsExplanation,
    };
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
    final d = defaults ??
        const GuidanceActionConfig(
          durationMinutes: 15,
          exactness: 0.0,
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation: '',
        );
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
      discoveryChance: _asOptionalDouble(
        yaml['discovery_chance'],
        d.discoveryChance,
      ),
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
      statsExplanation: _asString(yaml['stats_explanation'], d.statsExplanation),
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

  double get resolvedRangeM =>
      minRangeM + range * (maxRangeM - minRangeM);

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
    final d = defaults ??
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
      boundaryBlur:
          _asDouble(yaml['boundary_blur'], d.boundaryBlur).clamp(0.0, 1.0),
      statsExplanation: _asString(yaml['stats_explanation'], d.statsExplanation),
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
    final d = defaults ??
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
      minDurationMinutes:
          _asInt(yaml['min_duration_minutes'], d.minDurationMinutes),
      maxDurationMinutes:
          _asInt(yaml['max_duration_minutes'], d.maxDurationMinutes),
      ringIncrementM: _asDouble(yaml['ring_increment_m'], d.ringIncrementM),
      sweepPeriodS: _asDouble(yaml['sweep_period_s'], d.sweepPeriodS),
      statsExplanation: _asString(yaml['stats_explanation'], d.statsExplanation),
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
    final d = defaults ??
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
      boundaryBlur:
          _asDouble(yaml['boundary_blur'], d.boundaryBlur).clamp(0.0, 1.0),
      statsExplanation: _asString(yaml['stats_explanation'], d.statsExplanation),
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
      colors[entry.key.toString().trim().toLowerCase()] =
          _requireRgb(entry.value, entry.key.toString());
    }
    return RockTypeColorsConfig(formationMap: colors);
  }
}

class AerialMissionActionConfig {
  const AerialMissionActionConfig({
    required this.durationMinutes,
    required this.loopEndpointToleranceM,
    required this.flightSpeedKmh,
    required this.discoveryChance,
    required this.discoveryDistanceM,
    required this.ensureTimeoutS,
    required this.shortRouteWarnFraction,
    required this.statsExplanation,
  });

  final int durationMinutes;
  final double loopEndpointToleranceM;
  final double flightSpeedKmh;
  final double discoveryChance;
  final double discoveryDistanceM;
  final int ensureTimeoutS;
  final double shortRouteWarnFraction;
  final String statsExplanation;

  /// Derived draw/deploy limit: speed × duration.
  double get maxRouteKm => flightSpeedKmh * durationMinutes / 60.0;

  Map<String, dynamic> toParamsJson() => {
        'duration_minutes': durationMinutes,
        'loop_endpoint_tolerance_m': loopEndpointToleranceM,
        'flight_speed_kmh': flightSpeedKmh,
        'discovery_chance': discoveryChance,
        'discovery_distance_m': discoveryDistanceM,
        'ensure_timeout_s': ensureTimeoutS,
        'short_route_warn_fraction': shortRouteWarnFraction,
        'stats_explanation': statsExplanation,
      };

  factory AerialMissionActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    AerialMissionActionConfig? defaults,
  }) {
    final d = defaults ??
        const AerialMissionActionConfig(
          durationMinutes: 60,
          loopEndpointToleranceM: 75.0,
          flightSpeedKmh: 50.0,
          discoveryChance: 0.2,
          discoveryDistanceM: 200.0,
          ensureTimeoutS: 600,
          shortRouteWarnFraction: 0.7,
          statsExplanation:
              'Duration caps how far you can draw (speed × duration). Flight time is '
              'drawn length ÷ speed. Sites within discovery distance are rolled at the '
              'listed chance.',
        );
    return AerialMissionActionConfig(
      durationMinutes: _asInt(yaml['duration_minutes'], d.durationMinutes),
      loopEndpointToleranceM: _asDouble(
        yaml['loop_endpoint_tolerance_m'],
        d.loopEndpointToleranceM,
      ),
      flightSpeedKmh: _asDouble(yaml['flight_speed_kmh'], d.flightSpeedKmh),
      discoveryChance: _asDouble(yaml['discovery_chance'], d.discoveryChance),
      discoveryDistanceM: _asDouble(
        yaml['discovery_distance_m'],
        d.discoveryDistanceM,
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
