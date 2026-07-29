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

    expect(config.toolActions.aerialRecon.maxRouteKm, 50.0);
    expect(config.toolActions.aerialRecon.flightSpeedKmh, 50.0);
    expect(config.toolActions.aerialRecon.discoveryChance, 0.01);
    expect(config.toolActions.aerialRecon.discoveryDistanceM, 200.0);
    expect(config.toolActions.aerialRecon.shortRouteWarnFraction, 0.7);
    expect(
      config.toolActions.aerialRecon.statsExplanation,
      contains('Scout loops'),
    );
    expect(config.toolActions.aerialScout.maxRouteKm, 5.0);
    expect(config.toolActions.aerialScout.flightSpeedKmh, 35.0);
    expect(config.toolActions.aerialScout.discoveryChance, 0.008);
    expect(config.toolActions.aerialScout.discoveryDistanceM, 50.0);
    expect(
      config.toolActions.configFor('aerial_scout').maxRouteKm,
      5.0,
    );

    expect(config.toolActions.geoCompass.exactness, 0.0);
    expect(config.toolActions.geoCompass.discoveryChance, 0.9);
    expect(config.toolActions.geoCompass.durationMinutes, 15);
    expect(config.toolActions.geoCompass.maxDirectionRangeDeg, 180.0);
    expect(config.toolActions.geoCompass.minDirectionRangeDeg, 4.0);
    expect(config.toolActions.geoCompass.directionHintPeriodS, 3.0);
    expect(config.toolActions.proximityScanner.discoveryChance, isNull);
    expect(config.toolActions.siteNavigator.directionExactness, 0.0);
    expect(config.toolActions.siteNavigator.distanceExactness, 0.0);
    expect(
      config.toolActions.guidanceConfigFor('site_navigator').discoveryChance,
      0.9,
    );

    expect(config.toolActions.formationMap.durationMinutes, 10);
    expect(config.toolActions.formationMap.accuracy, 0.75);
    expect(config.toolActions.formationMap.range, 0.35);
    expect(config.toolActions.formationMap.minRangeM, 200.0);
    expect(config.toolActions.formationMap.maxRangeM, 2000.0);
    expect(config.toolActions.formationMap.resolvedRangeM, closeTo(830.0, 0.01));
    expect(config.toolActions.formationMap.baseAlpha, 0.48);
    expect(config.toolActions.formationMap.rangeFade, 0.85);
    expect(config.toolActions.formationMap.boundaryBlur, 0.8);
    expect(config.periodColors.formationMap.jurassic, (0x35, 0x68, 0x48));
    expect(config.periodColors.formationMap.cretaceous, (0xA8, 0x6B, 0x45));
    expect(config.periodColors.formationMap.triassic, (0xDD, 0x85, 0x00));
    expect(config.periodColors.siteMarkers.cretaceous, (0x8D, 0x6E, 0x63));
    expect(config.periodColors.siteMarkers.jurassic, (0x4F, 0x8F, 0x68));
    expect(config.periodColors.siteMarkers.triassic, (0xDD, 0x85, 0x00));
    expect(
      config.toolActions.formationMap.statsExplanation,
      contains('undiscovered field site'),
    );

    expect(config.leveling.rewards.siteDiscoverSiteDiscoveryXp, 10);
    expect(config.leveling.rewards.fossilDiscoverFossilDetectionXp, 5);
    expect(config.leveling.rewards.activeKmSiteDiscoveryXp, 30);
    expect(config.leveling.rewards.passiveKmSiteDiscoveryXp, 5);
    expect(config.leveling.skills.length, 11);
    expect(config.leveling.careerTitles.length, 99);

    expect(GameConfig.isLoaded, isTrue);
    expect(GameConfig.instance.siteDiscovery.maxDistanceM, 50.0);
  });

  test('instance throws before load', () {
    GameConfig.debugReset();
    expect(() => GameConfig.instance, throwsStateError);
  });
}
