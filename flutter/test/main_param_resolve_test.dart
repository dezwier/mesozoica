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
          'discovery_distance_m': ParamModifier(op: 'multiply', value: multiply),
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
          'discovery_distance_m': ParamModifier(op: 'multiply', value: multiply),
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
          'discovery_distance_m': ParamModifier(op: 'multiply', value: multiply),
          'discovery_chance': ParamModifier(op: 'multiply', value: multiply),
          'discovery_max_speed_kmh':
              ParamModifier(op: 'multiply', value: 3.0),
          'documentation_distance_m': ParamModifier(op: 'multiply', value: multiply),
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

  test('site stewardship estimation is base 1% times skill level', () async {
    await loadGameConfigForTest();

    final level1 = resolveSiteStewardshipAccuracies(skillLevel: 1);
    final level10 = resolveSiteStewardshipAccuracies(skillLevel: 10);
    final level99 = resolveSiteStewardshipAccuracies(skillLevel: 99);

    expect(level1['documentation_accuracy'], closeTo(0.01, 1e-9));
    expect(level10['documentation_accuracy'], closeTo(0.10, 1e-9));
    expect(level99['documentation_accuracy'], closeTo(0.99, 1e-9));
  });

  test('tool mods apply after level on site stewardship accuracies', () async {
    await loadGameConfigForTest();

    final result = resolveSiteStewardshipAccuracies(
      skillLevel: 10,
      toolMods: {
        'documentation_accuracy': const ParamModifier(op: 'add', value: 0.05),
      },
    );

    expect(result['documentation_accuracy'], closeTo(0.15, 1e-9));
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
    final base = GameConfig.instance.siteDiscovery.discoveryDistanceM;
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'day',
      ),
      closeTo(base * 1.1, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'golden_hour',
      ),
      closeTo(base * 1.3, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'dusk',
      ),
      closeTo(base, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'dawn',
      ),
      closeTo(base, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'night',
      ),
      closeTo(base * 0.6, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherType: 'clear',
      ),
      closeTo(base * 1.1, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherType: 'thunderstorm',
      ),
      closeTo(base * 0.8, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'night',
        weatherType: 'thunderstorm',
        toolBindings: [_ridgeUsing(multiply: 1.3)],
      ),
      closeTo(base * 0.6 * 0.8 * 1.3, 1e-9),
    );
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
    final base = GameConfig.instance.siteDiscovery.discoveryDistanceM;
    final bindings = [_nocturneUsing(multiply: 1.4)];
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'night',
        toolBindings: bindings,
      ),
      closeTo(base * 0.6 * 1.4, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'dusk',
        toolBindings: bindings,
      ),
      closeTo(base, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'day',
        toolBindings: bindings,
      ),
      closeTo(base * 1.1, 1e-9),
    );
  });

  test('mobility tools reduce site stewardship visibility', () async {
    await loadGameConfigForTest();
    final base = GameConfig.instance.siteStewardship.mainParams.documentationDistanceM;
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
    expect(
      resolveSiteStewardshipSiteVisibilityM(
        skillLevel: 1,
        weatherTime: 'day',
        toolBindings: [_mobilityUsing(multiply: 0.9)],
      ),
      closeTo(base * 1.1 * 0.9, 1e-9),
    );
  });
}
