import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';

import 'helpers/game_config_test_helpers.dart';

void main() {
  tearDown(() {
    GameConfig.debugReset();
  });

  test('loads shared YAML with current game defaults', () async {
    final config = await loadGameConfigForTest();

    expect(config.siteGeneration.cellSizeM, 500.0);
    expect(config.siteGeneration.client.nearbyRadiusKm, 0.5);

    expect(config.siteDiscovery.visibilityDistanceM, 20.0);
    expect(config.siteDiscovery.maxDistanceM, 20.0);
    expect(config.siteDiscovery.discoveryChance, 0.1);
    expect(config.siteDiscovery.maxDiscoverySpeedKmh, 15.0);
    expect(config.siteDiscovery.siteDiscoveryXp, 10.0);
    expect(config.siteDiscovery.activeKmXp, 30.0);
    expect(config.siteDiscovery.passiveKmXp, 5.0);
    expect(config.siteDiscovery.client.autoDiscoverRadiusM, 20.0);
    expect(config.siteDiscovery.client.cacheRadiusKm, 1.0);
    expect(config.siteDiscovery.client.cacheRefreshMoveThresholdM, 500.0);
    expect(config.siteDiscovery.client.discoverFailRetryS, 20);
    expect(config.siteDiscovery.client.discoveryRerollIntervalS, 10);

    expect(config.siteStewardship.mainParams.dinoAccuracy, 0.0);
    expect(config.siteStewardship.mainParams.fossilAccuracy, 0.0);
    expect(config.siteStewardship.mainParams.completenessAccuracy, 0.0);
    expect(config.siteStewardship.mainParams.qualityAccuracy, 0.0);
    expect(config.siteStewardship.mainParams.depthAccuracy, 0.0);
    final dinoAccMods = config.siteStewardship.levelModifiers['dino_accuracy']!;
    expect(dinoAccMods.length, 99);
    expect(dinoAccMods.first.level, 1);
    expect(dinoAccMods.first.value, 0.01);
    expect(dinoAccMods.last.level, 99);
    expect(dinoAccMods.last.value, 0.99);
    expect(config.siteStewardship.levelModifiers['fossil_accuracy']!.length, 99);
    expect(config.siteStewardship.oddNoise.dinoCount, 0.0);
    expect(config.siteStewardship.oddNoise.fossilCount, 0.5);
    expect(config.siteStewardship.oddNoise.completeness, 0.3);
    expect(config.siteStewardship.oddNoise.quality, 0.3);
    expect(config.siteStewardship.oddNoise.depth, 0.3);
    expect(config.siteStewardship.dinoCount.length, 6);
    expect(config.siteStewardship.dinoCount.first.count, 0);
    expect(config.siteStewardship.dinoCount.last.count, 5);
    expect(config.siteStewardship.fossilCount[6], 0.05);
    expect(config.siteStewardship.completenessWeights.isNotEmpty, isTrue);
    expect(config.siteStewardship.qualityWeights.isNotEmpty, isTrue);

    expect(config.fossilDetection.enabled, isFalse);
    expect(config.fossilExcavation.enabled, isFalse);
    expect(config.siteClearing.enabled, isFalse);

    expect(config.toolActions.aerialRecon.durationMinutes, 60);
    expect(config.toolActions.aerialRecon.flightSpeedKmh, 50.0);
    expect(config.toolActions.aerialRecon.maxRouteKm, 50.0);
    expect(config.toolActions.aerialRecon.flightDiscoveryChance, 0.01);
    expect(config.toolActions.aerialRecon.flightDiscoveryDistanceM, 200.0);
    expect(config.toolActions.aerialRecon.shortRouteWarnFraction, 0.7);
    expect(
      config.toolActions.aerialRecon.statsExplanation,
      contains('Flight time'),
    );
    expect(config.toolActions.aerialScout.durationMinutes, 10);
    expect(config.toolActions.aerialScout.flightSpeedKmh, 35.0);
    expect(config.toolActions.aerialScout.maxRouteKm, closeTo(35.0 * 10 / 60, 1e-9));
    expect(config.toolActions.aerialScout.flightDiscoveryChance, 0.008);
    expect(config.toolActions.aerialScout.flightDiscoveryDistanceM, 50.0);
    expect(
      config.toolActions.configFor('aerial_scout').durationMinutes,
      10,
    );

    expect(config.toolActions.geoCompass.exactness, 0.0);
    expect(config.toolActions.geoCompass.discoveryChance, 0.9);
    expect(
      config.toolActions.geoCompass.modifiesMainParams
          ?.affectsSkill('site_discovery'),
      isTrue,
    );
    expect(
      config.toolActions.geoCompass.modifiesMainParams
          ?.paramsFor('using', 'site_discovery')
          .containsKey('discovery_chance'),
      isTrue,
    );
    expect(config.toolActions.geoCompass.modifiesMainParams?.owning, isEmpty);
    expect(
      config.toolActions.siteNavigator.modifiesMainParams
          ?.paramsFor('using', 'site_discovery')
          .containsKey('discovery_chance'),
      isTrue,
    );
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

    expect(config.toolActions.orbitSurvey.durationMinutes, 10);
    expect(config.toolActions.orbitSurvey.accuracy, 0.75);
    expect(config.toolActions.orbitSurvey.range, 0.35);
    expect(config.toolActions.orbitSurvey.minRangeM, 200.0);
    expect(config.toolActions.orbitSurvey.maxRangeM, 2000.0);
    expect(config.toolActions.orbitSurvey.resolvedRangeM, closeTo(830.0, 0.01));
    expect(config.toolActions.orbitSurvey.baseAlpha, 0.48);
    expect(config.toolActions.orbitSurvey.rangeFade, 0.85);
    expect(config.toolActions.orbitSurvey.boundaryBlur, 1.0);
    expect(config.periodColors.orbitSurvey.jurassic, (0x35, 0x68, 0x48));
    expect(config.periodColors.orbitSurvey.cretaceous, (0xA8, 0x6B, 0x45));
    expect(config.periodColors.orbitSurvey.triassic, (0xDD, 0x85, 0x00));
    expect(config.periodColors.siteMarkers.cretaceous, (0x8D, 0x6E, 0x63));
    expect(config.periodColors.siteMarkers.jurassic, (0x4F, 0x8F, 0x68));
    expect(config.periodColors.siteMarkers.triassic, (0xDD, 0x85, 0x00));
    expect(
      config.toolActions.orbitSurvey.statsExplanation,
      contains('undiscovered field sites'),
    );

    expect(config.toolActions.formationMap.durationMinutes, 10);
    expect(config.toolActions.formationMap.cellSizeM, config.siteGeneration.cellSizeM);
    expect(config.toolActions.formationMap.widenessM, 500.0);
    expect(config.toolActions.formationMap.resolvedWidenessM, 500.0);
    expect(config.toolActions.formationMap.rangeFade, 0.0);
    expect(
      config.rockTypeColors.forRockType('sandstone'),
      (0xD4, 0xA0, 0x17),
    );

    expect(config.toolActions.ridgeGlass.durationMinutes, 60);
    expect(
      config.toolActions.ridgeGlass
          .siteDiscoveryMod('visibility_distance_m')
          ?.op,
      'multiply',
    );
    expect(
      config.toolActions.ridgeGlass
          .siteDiscoveryMod('visibility_distance_m')
          ?.value,
      1.3,
    );
    expect(
      config.toolActions.ridgeGlass.siteDiscoveryMod('discovery_chance')?.value,
      1.3,
    );
    expect(
      config.toolActions.ridgeGlass
          .siteDiscoveryMod('max_discovery_speed_kmh')
          ?.value,
      1.3,
    );
    expect(config.toolActions.ridgeGlass.addedVisibilityRangeM, isNull);
    expect(config.toolActions.ridgeGlass.addedDiscoveryRate, isNull);
    expect(
      config.toolActions.ridgeGlass.modifiesMainParams
          ?.affectsSkill('site_discovery'),
      isTrue,
    );

    expect(config.fossilDetection.mainParams['fossil_discovery_xp'], 5);
    expect(config.leveling.skills.length, 12);
    expect(config.leveling.skills.length, 12);
    expect(config.leveling.careerTitles.length, 99);

    expect(GameConfig.isLoaded, isTrue);
    expect(GameConfig.instance.siteDiscovery.maxDistanceM, 20.0);
  });

  test('instance throws before load', () {
    GameConfig.debugReset();
    expect(() => GameConfig.instance, throwsStateError);
  });
}
