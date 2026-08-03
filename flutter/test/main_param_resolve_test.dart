import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/config/main_param_resolve.dart';

import 'helpers/game_config_test_helpers.dart';

void main() {
  tearDown(() {
    GameConfig.debugReset();
  });

  test('site survey accuracies add 1% per skill level', () async {
    await loadGameConfigForTest();

    final level1 = resolveSiteSurveyAccuracies(skillLevel: 1);
    final level10 = resolveSiteSurveyAccuracies(skillLevel: 10);
    final level99 = resolveSiteSurveyAccuracies(skillLevel: 99);

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

  test('tool mods apply after level on site survey accuracies', () async {
    await loadGameConfigForTest();

    final result = resolveSiteSurveyAccuracies(
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
    // Inject a temporary owning visibility boost via resolve helpers' tool scan
    // by using a synthetic ParamModifier path through resolveScalarMainParam.
    final boosted = resolveScalarMainParam(
      base: 20,
      levelEntries: const [],
      skillLevel: 1,
      toolMod: const ParamModifier(op: 'add', value: 25),
    );
    expect(boosted, closeTo(45, 1e-9));
  });

  test('ridge glass using mods add visibility range', () async {
    await loadGameConfigForTest();
    final base = GameConfig.instance.siteDiscovery.visibilityDistanceM;
    final boosted = resolveSiteDiscoveryVisibilityDistanceM(
      skillLevel: 1,
      activeActionKey: 'ridge_glass',
    );
    expect(boosted, closeTo(base + 20, 1e-9));
  });

  test('weather_time night halves visibility before tools', () async {
    await loadGameConfigForTest();
    final base = GameConfig.instance.siteDiscovery.visibilityDistanceM;
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'day',
      ),
      closeTo(base, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'dusk',
      ),
      closeTo(base * 0.8, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'dawn',
      ),
      closeTo(base * 0.8, 1e-9),
    );
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'night',
      ),
      closeTo(base * 0.5, 1e-9),
    );
    // weather_time before tools: night *0.5 then ridge +20
    expect(
      resolveSiteDiscoveryVisibilityDistanceM(
        skillLevel: 1,
        weatherTime: 'night',
        activeActionKey: 'ridge_glass',
      ),
      closeTo(base * 0.5 + 20, 1e-9),
    );
  });
}
