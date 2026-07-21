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
  });

  final SiteGenerationConfig siteGeneration;
  final SiteDiscoveryConfig siteDiscovery;
  final FossilGenerationConfig fossilGeneration;
  final FossilDiscoveryConfig fossilDiscovery;
  final FossilExcavationConfig fossilExcavation;

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
    required this.dinoCountWeights,
    required this.cardCountWeights,
  });

  final Map<int, double> dinoCountWeights;
  final Map<int, double> cardCountWeights;

  factory FossilGenerationConfig.fromYaml(Map<String, dynamic> yaml) {
    return FossilGenerationConfig(
      dinoCountWeights: _asIntDoubleMap(yaml['dino_count_weights']),
      cardCountWeights: _asIntDoubleMap(yaml['card_count_weights']),
    );
  }
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
