// Terrain, main-parameter buff, and disguise action sections.

import 'config_parsing.dart';
import 'field_survey_config.dart';

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
      accuracy: configAsDouble(yaml['accuracy'], d.accuracy).clamp(0.0, 1.0),
      rangeM: configAsDouble(yaml['range_m'], d.rangeM),
      minRangeM: configAsDouble(yaml['min_range_m'], d.minRangeM),
      maxRangeM: configAsDouble(yaml['max_range_m'], d.maxRangeM),
      durationMinutes: configAsInt(yaml['duration_minutes'], d.durationMinutes),
      minDurationMinutes: configAsInt(
        yaml['min_duration_minutes'],
        d.minDurationMinutes,
      ),
      maxDurationMinutes: configAsInt(
        yaml['max_duration_minutes'],
        d.maxDurationMinutes,
      ),
      ringIncrementM: configAsDouble(
        yaml['ring_increment_m'],
        d.ringIncrementM,
      ),
      sweepPeriodS: configAsDouble(yaml['sweep_period_s'], d.sweepPeriodS),
      statsExplanation: configAsString(
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

  double? get addedDiscoveryDistanceM {
    final mod = siteDiscoveryMod('discovery_distance_m');
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
                'discovery_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 1.3,
                ),
                'discovery_chance': ParamModifier(op: 'multiply', value: 1.3),
                'discovery_max_speed_kmh': ParamModifier(
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
      mods = ModifiesMainParams.fromYaml(configAsMap(rawMods));
    }
    List<String>? activeTimes = d.activeWeatherTimes;
    final rawTimes = yaml['active_weather_times'];
    if (rawTimes is List) {
      activeTimes = rawTimes.map((e) => e.toString()).toList();
    }
    return MainParamBuffActionConfig(
      durationMinutes: configAsInt(yaml['duration_minutes'], d.durationMinutes),
      modifiesMainParams: mods,
      activeWeatherTimes: activeTimes,
      statsExplanation: configAsString(
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

  ParamModifier? get rivalDiscoveryChanceMod =>
      siteStewardshipMod('rival_discovery_chance');

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
                'rival_discovery_chance': ParamModifier(
                  op: 'multiply',
                  value: 0.5,
                ),
              },
            },
          ),
          statsExplanation: '',
        );
    ModifiesMainParams? mods = d.modifiesMainParams;
    final rawMods = yaml['modifies_main_params'];
    if (rawMods is Map) {
      mods = ModifiesMainParams.fromYaml(configAsMap(rawMods));
    } else if (yaml.containsKey('discovery_chance_multiplier')) {
      // Legacy bare multiplier → formalize as rival_discovery_chance multiply.
      final value = configAsDouble(yaml['discovery_chance_multiplier'], 0.5);
      mods = ModifiesMainParams(
        using: {
          'field_survey': {
            'rival_discovery_chance': ParamModifier(
              op: 'multiply',
              value: value,
            ),
          },
        },
      );
    }
    return DisguiseActionConfig(
      durationMinutes: configAsInt(yaml['duration_minutes'], d.durationMinutes),
      modifiesMainParams: mods,
      statsExplanation: configAsString(
        yaml['stats_explanation'],
        d.statsExplanation,
      ),
    );
  }
}
