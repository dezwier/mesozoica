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
        'site_discovery': {
          'visibility_distance_m': ParamModifier(op: 'multiply', value: multiply),
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
        'site_discovery': {
          'visibility_distance_m': ParamModifier(op: 'multiply', value: multiply),
          'discovery_chance': ParamModifier(op: 'multiply', value: multiply),
        },
      },
    ),
    applyUsing: true,
    activeWeatherTimes: const ['night'],
  );
}

void main() {
  tearDown(() {
    GameConfig.debugReset();
  });

  test('site stewardship estimations are base 1% times skill level', () async {
    await loadGameConfigForTest();

    final level1 = resolveSiteStewardshipAccuracies(skillLevel: 1);
    final level10 = resolveSiteStewardshipAccuracies(skillLevel: 10);
    final level99 = resolveSiteStewardshipAccuracies(skillLevel: 99);

    for (final key in [
      'dino_accuracy',
      'fossil_accuracy',
      'completeness_accuracy',
      'quality_accuracy',
      'depth_accuracy',
    ]) {
      expect(level1[key], closeTo(0.01, 1e-9), reason: key);
      expect(level10[key], closeTo(0.10, 1e-9), reason: key);
      expect(level99[key], closeTo(0.99, 1e-9), reason: key);
    }
  });

  test('tool mods apply after level on site stewardship accuracies', () async {
    await loadGameConfigForTest();

    final result = resolveSiteStewardshipAccuracies(
      skillLevel: 10,
      toolMods: {
        'dino_accuracy': const ParamModifier(op: 'add', value: 0.05),
      },
    );

    expect(result['dino_accuracy'], closeTo(0.15, 1e-9));
    expect(result['fossil_accuracy'], closeTo(0.10, 1e-9));
  });

  test('site discovery visibility defaults to main param', () async {
    await loadGameConfigForTest();
    final base = GameConfig.instance.siteDiscovery.visibilityDistanceM;
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
    final base = GameConfig.instance.siteDiscovery.visibilityDistanceM;
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
    final base = GameConfig.instance.siteDiscovery.visibilityDistanceM;
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
          'site_discovery': {
            'visibility_distance_m': {'op': 'multiply', 'value': 1.4},
          },
        },
      },
    });
    expect(mods, isNotNull);
    expect(
      mods!.paramsFor('using', 'site_discovery')['visibility_distance_m']?.value,
      1.4,
    );
  });

  test('nocturne using mods apply only at night', () async {
    await loadGameConfigForTest();
    final base = GameConfig.instance.siteDiscovery.visibilityDistanceM;
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
}
