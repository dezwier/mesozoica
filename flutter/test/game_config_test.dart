import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';

import 'helpers/game_config_test_helpers.dart';

void main() {
  tearDown(() {
    GameConfig.debugReset();
  });

  test('loads shared YAML with current game defaults', () async {
    final config = await loadGameConfigForTest();

    expect(config.siteGeneration.client.ensureMoveThresholdM, 250.0);
    expect(config.siteGeneration.client.nearbyRadiusKm, 0.5);

    expect(config.siteDiscovery.maxDistanceM, 50.0);
    expect(config.siteDiscovery.discoveryChance, 0.1);
    expect(config.siteDiscovery.client.autoDiscoverRadiusM, 50.0);
    expect(config.siteDiscovery.client.cacheRadiusKm, 1.0);
    expect(config.siteDiscovery.client.cacheRefreshMoveThresholdM, 500.0);
    expect(config.siteDiscovery.client.discoverFailRetryS, 20);

    expect(config.fossilGeneration.oddNoise.dinoCount, 0.0);
    expect(config.fossilGeneration.oddNoise.fossilCount, 0.5);
    expect(config.fossilGeneration.oddNoise.completeness, 0.3);
    expect(config.fossilGeneration.oddNoise.quality, 0.3);
    expect(config.fossilGeneration.oddNoise.depth, 0.3);
    expect(config.fossilGeneration.dinoCountThresholds.length, 6);
    expect(config.fossilGeneration.dinoCountThresholds.first.count, 0);
    expect(config.fossilGeneration.dinoCountThresholds.last.count, 5);
    expect(config.fossilGeneration.cardCountWeights[6], 0.05);

    expect(config.fossilDiscovery.enabled, isFalse);
    expect(config.fossilExcavation.enabled, isFalse);

    expect(config.toolActions.aerialRecon.maxRouteKm, 100.0);
    expect(config.toolActions.aerialRecon.flightSpeedKmh, 50.0);
    expect(config.toolActions.aerialRecon.discoveryChance, 0.01);
    expect(config.toolActions.aerialRecon.discoveryDistanceM, 200.0);
    expect(config.toolActions.aerialRecon.shortRouteWarnFraction, 0.7);
    expect(
      config.toolActions.aerialRecon.statsExplanation,
      contains('Scout loops'),
    );
    expect(config.toolActions.aerialScout.maxRouteKm, 30.0);
    expect(config.toolActions.aerialScout.flightSpeedKmh, 35.0);
    expect(config.toolActions.aerialScout.discoveryChance, 0.008);
    expect(config.toolActions.aerialScout.discoveryDistanceM, 120.0);
    expect(
      config.toolActions.configFor('aerial_scout').maxRouteKm,
      30.0,
    );

    expect(GameConfig.isLoaded, isTrue);
    expect(GameConfig.instance.siteDiscovery.maxDistanceM, 50.0);
  });

  test('instance throws before load', () {
    GameConfig.debugReset();
    expect(() => GameConfig.instance, throwsStateError);
  });
}
