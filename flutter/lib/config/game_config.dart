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
  });

  final SiteGenerationConfig siteGeneration;
  final SiteDiscoveryConfig siteDiscovery;
  final FossilGenerationConfig fossilGeneration;
  final FossilDiscoveryConfig fossilDiscovery;
  final FossilExcavationConfig fossilExcavation;
  final ToolActionsConfig toolActions;

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
  const SiteGenerationConfig({required this.client});

  final SiteGenerationClientConfig client;

  factory SiteGenerationConfig.fromYaml(Map<String, dynamic> yaml) {
    return SiteGenerationConfig(
      client: SiteGenerationClientConfig.fromYaml(
        GameConfig._asMap(yaml['client']),
      ),
    );
  }
}

class SiteGenerationClientConfig {
  const SiteGenerationClientConfig({
    required this.ensureMoveThresholdM,
    required this.nearbyRadiusKm,
  });

  final double ensureMoveThresholdM;
  final double nearbyRadiusKm;

  factory SiteGenerationClientConfig.fromYaml(Map<String, dynamic> yaml) {
    return SiteGenerationClientConfig(
      ensureMoveThresholdM: _asDouble(yaml['ensure_move_threshold_m'], 500.0),
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
  });

  final AerialMissionActionConfig aerialRecon;
  final AerialMissionActionConfig aerialScout;

  AerialMissionActionConfig configFor(String actionKey) {
    switch (actionKey) {
      case 'aerial_scout':
        return aerialScout;
      case 'aerial_recon':
      default:
        return aerialRecon;
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
          maxRouteKm: 30.0,
          loopEndpointToleranceM: 75.0,
          flightSpeedKmh: 35.0,
          discoveryChance: 0.008,
          discoveryDistanceM: 120.0,
          ensureSampleSpacingKm: 0.5,
          ensureTimeoutS: 600,
          shortRouteWarnFraction: 0.7,
          statsExplanation:
              'Drone loops fly at this speed within the max range; sites within '
              'discovery distance are rolled at the listed chance.',
        ),
      ),
    );
  }
}

class AerialMissionActionConfig {
  const AerialMissionActionConfig({
    required this.maxRouteKm,
    required this.loopEndpointToleranceM,
    required this.flightSpeedKmh,
    required this.discoveryChance,
    required this.discoveryDistanceM,
    required this.ensureSampleSpacingKm,
    required this.ensureTimeoutS,
    required this.shortRouteWarnFraction,
    required this.statsExplanation,
  });

  final double maxRouteKm;
  final double loopEndpointToleranceM;
  final double flightSpeedKmh;
  final double discoveryChance;
  final double discoveryDistanceM;
  final double ensureSampleSpacingKm;
  final int ensureTimeoutS;
  final double shortRouteWarnFraction;
  final String statsExplanation;

  factory AerialMissionActionConfig.fromYaml(
    Map<String, dynamic> yaml, {
    AerialMissionActionConfig? defaults,
  }) {
    final d = defaults ??
        const AerialMissionActionConfig(
          maxRouteKm: 100.0,
          loopEndpointToleranceM: 75.0,
          flightSpeedKmh: 50.0,
          discoveryChance: 0.2,
          discoveryDistanceM: 200.0,
          ensureSampleSpacingKm: 0.5,
          ensureTimeoutS: 600,
          shortRouteWarnFraction: 0.7,
          statsExplanation:
              'Scout loops fly at this speed within the max range; sites within '
              'discovery distance are rolled at the listed chance.',
        );
    return AerialMissionActionConfig(
      maxRouteKm: _asDouble(yaml['max_route_km'], d.maxRouteKm),
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
      ensureSampleSpacingKm: _asDouble(
        yaml['ensure_sample_spacing_km'],
        d.ensureSampleSpacingKm,
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
