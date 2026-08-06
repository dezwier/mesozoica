import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/config/main_param_resolve.dart';
import 'package:mesozoica/config/tool_instance_params.dart';

import 'helpers/game_config_test_helpers.dart';

ToolModBinding _ridgeUsing({required double multiply}) {
  return ToolModBinding(
    actionKey: 'ridge_glass',
    toolName: 'Ridge Glass',
    mods: ModifiesMainParams(
      using: {
        'field_survey': {
          'discovery_distance_m': ParamModifier(
            op: 'multiply',
            value: multiply,
          ),
          'discovery_chance': ParamModifier(op: 'multiply', value: multiply),
        },
      },
    ),
    applyUsing: true,
  );
}

ToolModBinding _nocturneUsing({required double multiply}) {
  return ToolModBinding(
    actionKey: 'nocturne_lens',
    toolName: 'Nocturne Lens',
    mods: ModifiesMainParams(
      using: {
        'field_survey': {
          'discovery_distance_m': ParamModifier(
            op: 'multiply',
            value: multiply,
          ),
          'discovery_chance': ParamModifier(op: 'multiply', value: multiply),
        },
      },
    ),
    applyUsing: true,
    activeWeatherTimes: const ['night'],
  );
}

ToolModBinding _mobilityUsing({required double multiply}) {
  return ToolModBinding(
    actionKey: 'expedition_drivetrain',
    toolName: 'Expedition Drivetrain',
    mods: ModifiesMainParams(
      using: {
        'field_survey': {
          'discovery_distance_m': ParamModifier(
            op: 'multiply',
            value: multiply,
          ),
          'discovery_chance': ParamModifier(op: 'multiply', value: multiply),
          'discovery_max_speed_kmh': ParamModifier(op: 'multiply', value: 3.0),
          'documentation_distance_m': ParamModifier(
            op: 'multiply',
            value: multiply,
          ),
        },
      },
    ),
    applyUsing: true,
  );
}

void main() {
  tearDown(() {
    GameConfig.debugReset();
  });

  test('applyLevelModifiers lerps between sparse endpoints', () {
    const entries = [
      LevelModifierEntry(level: 1, op: 'multiply', value: 1),
      LevelModifierEntry(level: 99, op: 'multiply', value: 0.5),
    ];
    expect(applyLevelModifiers(1.0, entries, 1), closeTo(1.0, 1e-9));
    expect(applyLevelModifiers(1.0, entries, 50), closeTo(0.75, 1e-9));
    expect(applyLevelModifiers(1.0, entries, 99), closeTo(0.5, 1e-9));
  });

  test('site stewardship estimation follows level modifiers', () async {
    await loadGameConfigForTest();
    final cfg = GameConfig.instance.siteStewardship;
    final base = cfg.mainParams.documentationAccuracy;
    final entries = cfg.levelModifiers['documentation_accuracy'];

    for (final level in [1, 10, 99]) {
      final resolved = resolveSiteStewardshipAccuracies(skillLevel: level);
      expect(
        resolved['documentation_accuracy'],
        closeTo(
          applyLevelModifiers(base, entries, level).clamp(0.0, 1.0),
          1e-9,
        ),
      );
    }
  });

  test('tool mods apply after level on site stewardship accuracies', () async {
    await loadGameConfigForTest();
    final cfg = GameConfig.instance.siteStewardship;
    final base = cfg.mainParams.documentationAccuracy;
    final entries = cfg.levelModifiers['documentation_accuracy'];
    const toolAdd = 0.05;
    final at10 = applyLevelModifiers(base, entries, 10);

    final result = resolveSiteStewardshipAccuracies(
      skillLevel: 10,
      toolMods: {
        'documentation_accuracy': const ParamModifier(
          op: 'add',
          value: toolAdd,
        ),
      },
    );

    expect(
      result['documentation_accuracy'],
      closeTo((at10 + toolAdd).clamp(0.0, 1.0), 1e-9),
    );
  });

  test('site discovery visibility defaults to main param', () async {
    await loadGameConfigForTest();
    final base = GameConfig.instance.siteDiscovery.discoveryDistanceM;
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(skillLevel: 1),
      closeTo(base, 1e-9),
    );
  });

  test('site discovery visibility applies owning tool add', () async {
    await loadGameConfigForTest();
    final boosted = resolveScalarMainParam(
      base: 20,
      levelEntries: const [],
      skillLevel: 1,
      toolMod: const ParamModifier(op: 'add', value: 25),
    );
    expect(boosted, closeTo(45, 1e-9));
  });

  test('ridge glass using mods come from instance bindings not yaml', () async {
    await loadGameConfigForTest();
    final base = GameConfig.instance.siteDiscovery.discoveryDistanceM;
    // Instance is 1.4 even if YAML baseline differs.
    final boosted = resolveSiteDiscoveryVisibilityDistanceM(
      skillLevel: 1,
      toolBindings: [_ridgeUsing(multiply: 1.4)],
    );
    expect(boosted, closeTo(base * 1.4, 1e-9));
    // Without bindings, YAML is never auto-applied.
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(skillLevel: 1),
      closeTo(base, 1e-9),
    );
  });

  test('weather_time and weather_type stack before tools', () async {
    await loadGameConfigForTest();
    final disc = GameConfig.instance.siteDiscovery;
    final base = disc.discoveryDistanceM;

    double expected({
      String? weatherTime,
      String? weatherType,
      List<ToolModBinding> toolBindings = const [],
    }) {
      return resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: weatherTime,
        weatherType: weatherType,
        toolBindings: toolBindings,
      );
    }

    // Sanity: identity path when no ambient key.
    expect(expected(), closeTo(base, 1e-9));

    for (final period in ['day', 'golden_hour', 'dusk', 'dawn', 'night']) {
      expect(
        expected(weatherTime: period),
        closeTo(
          resolveScalarMainParam(
            base: base,
            levelEntries: const [],
            skillLevel: 1,
            weatherTimeMods: weatherTimeModsForParam(
              weatherTimeModifiers: disc.weatherTimeModifiers,
              paramKey: 'discovery_distance_m',
              weatherTime: period,
            ),
          ),
          1e-9,
        ),
      );
    }

    for (final type in ['clear', 'thunderstorm']) {
      expect(
        expected(weatherType: type),
        closeTo(
          resolveScalarMainParam(
            base: base,
            levelEntries: const [],
            skillLevel: 1,
            weatherTypeMods: weatherTypeModsForParam(
              weatherTypeModifiers: disc.weatherTypeModifiers,
              paramKey: 'discovery_distance_m',
              weatherType: type,
            ),
          ),
          1e-9,
        ),
      );
    }

    // Ambient before tools: stacked resolve matches helper.
    final stacked = expected(
      weatherTime: 'night',
      weatherType: 'thunderstorm',
      toolBindings: [_ridgeUsing(multiply: 1.3)],
    );
    var manual = resolveScalarMainParam(
      base: base,
      levelEntries: const [],
      skillLevel: 1,
      weatherTimeMods: weatherTimeModsForParam(
        weatherTimeModifiers: disc.weatherTimeModifiers,
        paramKey: 'discovery_distance_m',
        weatherTime: 'night',
      ),
      weatherTypeMods: weatherTypeModsForParam(
        weatherTypeModifiers: disc.weatherTypeModifiers,
        paramKey: 'discovery_distance_m',
        weatherType: 'thunderstorm',
      ),
    );
    manual = applyMainParamModifier(manual, op: 'multiply', value: 1.3);
    expect(stacked, closeTo(manual, 1e-9));
  });

  test('modifiesMainParamsFromParams parses instance payload', () {
    final mods = modifiesMainParamsFromParams({
      'modifies_main_params': {
        'using': {
          'field_survey': {
            'discovery_distance_m': {'op': 'multiply', 'value': 1.4},
          },
        },
      },
    });
    expect(mods, isNotNull);
    expect(
      mods!.paramsFor('using', 'field_survey')['discovery_distance_m']?.value,
      1.4,
    );
  });

  test('nocturne using mods apply only at night', () async {
    await loadGameConfigForTest();
    final disc = GameConfig.instance.siteDiscovery;
    final base = disc.discoveryDistanceM;
    final bindings = [_nocturneUsing(multiply: 1.4)];

    for (final period in ['night', 'dusk', 'day']) {
      final got = resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: period,
        toolBindings: bindings,
      );
      var expected = resolveScalarMainParam(
        base: base,
        levelEntries: const [],
        skillLevel: 1,
        weatherTimeMods: weatherTimeModsForParam(
          weatherTimeModifiers: disc.weatherTimeModifiers,
          paramKey: 'discovery_distance_m',
          weatherTime: period,
        ),
      );
      if (period == 'night') {
        expected = applyMainParamModifier(expected, op: 'multiply', value: 1.4);
      }
      expect(got, closeTo(expected, 1e-9));
    }
  });

  test('mobility tools reduce site stewardship visibility', () async {
    await loadGameConfigForTest();
    final stew = GameConfig.instance.siteStewardship;
    final base = stew.mainParams.documentationDistanceM;
    expect(
      resolveSiteStewardshipSiteVisibilityM(skillLevel: 1),
      closeTo(base, 1e-9),
    );
    expect(
      resolveSiteStewardshipSiteVisibilityM(
        skillLevel: 1,
        toolBindings: [_mobilityUsing(multiply: 0.9)],
      ),
      closeTo(base * 0.9, 1e-9),
    );

    final withDay = resolveSiteStewardshipSiteVisibilityM(
      skillLevel: 1,
      weatherTime: 'day',
      toolBindings: [_mobilityUsing(multiply: 0.9)],
    );
    final ambient = resolveScalarMainParam(
      base: base,
      levelEntries: const [],
      skillLevel: 1,
      weatherTimeMods: weatherTimeModsForParam(
        weatherTimeModifiers: stew.weatherTimeModifiers,
        paramKey: 'documentation_distance_m',
        weatherTime: 'day',
      ),
    );
    expect(withDay, closeTo(ambient * 0.9, 1e-9));
  });
}
