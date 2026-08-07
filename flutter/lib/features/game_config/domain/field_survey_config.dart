// Typed parsers for field-survey and skill-domain YAML documents.

import 'config_parsing.dart';
import 'skill_modifiers_config.dart';

export 'skill_modifiers_config.dart';

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
  double get discoveryMaxSpeedKmh => mainParams.discoveryMaxSpeedKmh;
  double get discoverSiteXp => mainParams.discoverSiteXp;
  double get discoverSiteAsFirstXp => mainParams.discoverSiteAsFirstXp;
  double get explore100mActivelyXp => mainParams.explore100mActivelyXp;
  double get explore100mPassivelyXp => mainParams.explore100mPassivelyXp;
  double get disguiseOfSiteXp => mainParams.disguiseOfSiteXp;
  double get documentSiteXp => mainParams.documentSiteXp;
  double get documentSiteAsFirstXp => mainParams.documentSiteAsFirstXp;
  double get identifySiteXp => mainParams.identifySiteXp;
  double get documentSpeed => mainParams.documentSpeed;
  double get rivalDiscoveryChance => mainParams.rivalDiscoveryChance;

  /// Back-compat aliases for distribution tables.
  List<DinoCountThreshold> get dinoCountThresholds => dinoCount;
  Map<int, double> get cardCountWeights => fossilCount;
  List<FossilDepthBucket> get depthBuckets => depthWeights;

  factory FieldSurveyConfig.fromYaml(Map<String, dynamic> yaml) {
    final main = configAsMap(yaml['main_params']);
    final rawBuckets = yaml['depth_weights'] ?? yaml['depth_buckets'];
    final buckets = <FossilDepthBucket>[];
    if (rawBuckets is List) {
      for (final entry in rawBuckets) {
        if (entry is Map) {
          buckets.add(
            FossilDepthBucket(
              weight: configAsDouble(entry['weight'], 0),
              minCm: configAsInt(entry['min_cm'], 0),
              maxCm: configAsInt(entry['max_cm'], 0),
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
              maxOdd: configAsDouble(entry['max_odd'], 0),
              count: configAsInt(entry['count'], 0),
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
      client: FieldSurveyClientConfig.fromYaml(configAsMap(yaml['client'])),
      dinoCount: thresholds,
      fossilCount: configAsIntDoubleMap(
        yaml['fossil_count'] ?? yaml['card_count_weights'],
      ),
      depthWeights: buckets,
      completenessWeights: configAsStringDoubleMap(
        yaml['completeness_weights'],
      ),
      qualityWeights: configAsStringDoubleMap(yaml['quality_weights']),
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
    required this.discoveryMaxSpeedKmh,
    required this.discoverSiteXp,
    required this.discoverSiteAsFirstXp,
    required this.explore100mActivelyXp,
    required this.explore100mPassivelyXp,
    required this.documentAccuracy,
    required this.rivalDiscoveryChance,
    required this.documentSpeed,
    required this.disguiseOfSiteXp,
    required this.documentSiteXp,
    required this.documentSiteAsFirstXp,
    required this.identifySiteXp,
  });

  final double visibilityDistanceM;
  final double discoveryChance;
  final double discoveryMaxSpeedKmh;
  final double discoverSiteXp;
  final double discoverSiteAsFirstXp;
  final double explore100mActivelyXp;
  final double explore100mPassivelyXp;
  final double documentAccuracy;
  final double rivalDiscoveryChance;
  final double documentSpeed;
  final double disguiseOfSiteXp;
  final double documentSiteXp;
  final double documentSiteAsFirstXp;
  final double identifySiteXp;

  factory FieldSurveyMainParams.fromYaml(Map<String, dynamic> yaml) {
    return FieldSurveyMainParams(
      visibilityDistanceM: configAsDouble(yaml['visibility_distance_m'], 20.0),
      discoveryChance: configAsDouble(yaml['discovery_chance'], 0.1),
      discoveryMaxSpeedKmh: configAsDouble(
        yaml['discovery_max_speed_kmh'],
        10.0,
      ),
      discoverSiteXp: configAsDouble(yaml['discover_site_xp'], 20.0),
      discoverSiteAsFirstXp: configAsDouble(
        yaml['discover_site_as_first_xp'],
        20.0,
      ),
      explore100mActivelyXp: configAsDouble(
        yaml['explore_100m_actively_xp'],
        20.0,
      ),
      explore100mPassivelyXp: configAsDouble(
        yaml['explore_100m_passively_xp'],
        10.0,
      ),
      documentAccuracy: configAsDouble(yaml['document_accuracy'], 0.01),
      rivalDiscoveryChance: configAsDouble(yaml['rival_discovery_chance'], 1),
      documentSpeed: configAsDouble(yaml['document_speed'], 0.01),
      disguiseOfSiteXp: configAsDouble(yaml['disguise_of_site_xp'], 40),
      documentSiteXp: configAsDouble(yaml['document_site_xp'], 80),
      documentSiteAsFirstXp: configAsDouble(
        yaml['document_site_as_first_xp'],
        20,
      ),
      identifySiteXp: configAsDouble(yaml['identify_site_xp'], 40),
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
      autoDiscoverRadiusM: configAsDouble(yaml['auto_discover_radius_m'], 20.0),
      cacheRadiusKm: configAsDouble(yaml['cache_radius_km'], 1.0),
      cacheRefreshMoveThresholdM: configAsDouble(
        yaml['cache_refresh_move_threshold_m'],
        500.0,
      ),
      discoverFailRetryS: configAsInt(yaml['discover_fail_retry_s'], 20),
      discoveryRerollIntervalS: configAsInt(
        yaml['discovery_reroll_interval_s'],
        10,
      ),
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
        dinoCount: configAsDouble(raw['dino_count'], 0.3),
        fossilCount: configAsDouble(raw['fossil_count'], 0.3),
        completeness: configAsDouble(raw['completeness'], 0.3),
        quality: configAsDouble(raw['quality'], 0.3),
        depth: configAsDouble(raw['depth'], 0.3),
      );
    }
    // Legacy scalar odd_noise: apply the same value to every sampler.
    final shared = configAsDouble(raw, 0.3);
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
      maxDelta: configAsDouble(raw['max_delta'], defaults.maxDelta),
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
