// Guidance and orbital-navigation action sections.

import 'config_parsing.dart';
import 'field_survey_config.dart';

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
      mods = ModifiesMainParams.fromYaml(configAsMap(rawMods));
    } else if (yaml.containsKey('discovery_chance')) {
      // Legacy bare discovery_chance → formalize as replace modifier.
      final chance = configAsOptionalDouble(yaml['discovery_chance'], null);
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
      durationMinutes: configAsInt(yaml['duration_minutes'], d.durationMinutes),
      exactness: configAsOptionalDouble(yaml['exactness'], d.exactness),
      directionExactness: configAsOptionalDouble(
        yaml['direction_exactness'],
        d.directionExactness,
      ),
      distanceExactness: configAsOptionalDouble(
        yaml['distance_exactness'],
        d.distanceExactness,
      ),
      modifiesMainParams: mods,
      directionHintPeriodS: configAsDouble(
        yaml['direction_hint_period_s'],
        d.directionHintPeriodS,
      ),
      maxDirectionRangeDeg: configAsDouble(
        yaml['max_direction_range_deg'],
        d.maxDirectionRangeDeg,
      ),
      minDirectionRangeDeg: configAsDouble(
        yaml['min_direction_range_deg'],
        d.minDirectionRangeDeg,
      ),
      statsExplanation: configAsString(
        yaml['stats_explanation'],
        d.statsExplanation,
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
      durationMinutes: configAsInt(yaml['duration_minutes'], d.durationMinutes),
      accuracy: configAsDouble(yaml['accuracy'], d.accuracy).clamp(0.0, 1.0),
      range: configAsDouble(yaml['range'], d.range).clamp(0.0, 1.0),
      minRangeM: configAsDouble(yaml['min_range_m'], d.minRangeM),
      maxRangeM: configAsDouble(yaml['max_range_m'], d.maxRangeM),
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
