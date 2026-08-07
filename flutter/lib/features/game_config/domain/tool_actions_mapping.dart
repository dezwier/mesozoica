// Formation-map and aerial action sections.

import 'config_parsing.dart';

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
      durationMinutes: configAsInt(yaml['duration_minutes'], d.durationMinutes),
      accuracy: configAsDouble(yaml['accuracy'], d.accuracy).clamp(0.0, 1.0),
      widenessM: configAsDouble(yaml['wideness_m'], d.widenessM),
      minWidenessM: configAsDouble(yaml['min_wideness_m'], d.minWidenessM),
      maxWidenessM: configAsDouble(yaml['max_wideness_m'], d.maxWidenessM),
      cellSizeM: configAsDouble(yaml['cell_size_m'], d.cellSizeM),
      baseAlpha: configAsDouble(
        yaml['base_alpha'],
        d.baseAlpha,
      ).clamp(0.0, 1.0),
      rangeFade: configAsDouble(
        yaml['range_fade'],
        d.rangeFade,
      ).clamp(0.0, 1.0),
      boundaryBlur: configAsDouble(
        yaml['boundary_blur'],
        d.boundaryBlur,
      ).clamp(0.0, 1.0),
      statsExplanation: configAsString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
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
              'Sites within flight visibility distance are rolled at the listed chance.',
        );
    return AerialActionConfig(
      durationMinutes: configAsInt(yaml['duration_minutes'], d.durationMinutes),
      loopEndpointToleranceM: configAsDouble(
        yaml['loop_endpoint_tolerance_m'],
        d.loopEndpointToleranceM,
      ),
      flightSpeedKmh: configAsDouble(
        yaml['flight_speed_kmh'],
        d.flightSpeedKmh,
      ),
      flightDiscoveryChance: configAsDouble(
        yaml['flight_discovery_chance'] ?? yaml['discovery_chance'],
        d.flightDiscoveryChance,
      ),
      flightDiscoveryDistanceM: configAsDouble(
        yaml['flight_discovery_distance_m'] ?? yaml['visibility_distance_m'],
        d.flightDiscoveryDistanceM,
      ),
      ensureTimeoutS: configAsInt(yaml['ensure_timeout_s'], d.ensureTimeoutS),
      shortRouteWarnFraction: configAsDouble(
        yaml['short_route_warn_fraction'],
        d.shortRouteWarnFraction,
      ),
      statsExplanation: configAsString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}
