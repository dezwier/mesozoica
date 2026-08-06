import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';

import 'helpers/game_config_test_helpers.dart';

void main() {
  tearDown(() {
    GameConfig.debugReset();
  });

  test('loads shared YAML with expected structure', () async {
    final config = await loadGameConfigForTest();

    expect(config.siteGeneration.cellSizeM, greaterThan(0));
    expect(config.siteGeneration.client.nearbyRadiusKm, greaterThan(0));

    final disc = config.siteDiscovery;
    expect(disc.discoveryDistanceM, greaterThan(0));
    expect(disc.maxDistanceM, disc.discoveryDistanceM);
    expect(disc.discoveryChance, greaterThan(0));
    expect(disc.discoveryChance, lessThanOrEqualTo(1));
    expect(disc.discoveryMaxSpeedKmh, greaterThan(0));
    expect(disc.discoverSiteXp, greaterThan(0));
    expect(disc.client.autoDiscoverRadiusM, greaterThan(0));

    final stew = config.siteStewardship;
    expect(stew.mainParams.documentationAccuracy, greaterThan(0));
    expect(stew.mainParams.documentationAccuracy, lessThanOrEqualTo(1));
    expect(stew.mainParams.documentationDistanceM, greaterThan(0));
    expect(stew.mainParams.documentProgressXp, greaterThan(0));
    final accMods = stew.levelModifiers['documentation_accuracy']!;
    expect(accMods.length, greaterThanOrEqualTo(2));
    expect(accMods.first.op, 'multiply');
    final rivalMods = stew.levelModifiers['rival_discovery_chance']!;
    expect(rivalMods.length, greaterThanOrEqualTo(2));
    expect(rivalMods.first.op, 'multiply');
    expect(stew.levelModifiers.containsKey('documentation_genera'), isFalse);
    expect(stew.accuracyNoise.maxDelta, greaterThan(0));
    expect(stew.dinoCount.length, greaterThanOrEqualTo(2));
    expect(stew.dinoCount.first.count, 0);
    expect(stew.fossilCount, isNotEmpty);
    expect(stew.completenessWeights, isNotEmpty);
    expect(stew.qualityWeights, isNotEmpty);

    expect(config.boneQuarry.enabled, isTrue);
    expect(config.scienceHall.enabled, isFalse);

    expect(config.toolActions.aerialRecon.durationMinutes, greaterThan(0));
    expect(config.toolActions.aerialRecon.flightSpeedKmh, greaterThan(0));
    expect(
      config.toolActions.aerialRecon.flightDiscoveryChance,
      greaterThan(0),
    );
    expect(
      config.toolActions.aerialRecon.statsExplanation,
      contains('Flight time'),
    );
    expect(config.toolActions.aerialScout.durationMinutes, greaterThan(0));
    expect(
      config.toolActions.configFor('aerial_scout').durationMinutes,
      config.toolActions.aerialScout.durationMinutes,
    );

    expect(
      config.toolActions.geoCompass.modifiesMainParams?.affectsSkill(
        'field_survey',
      ),
      isTrue,
    );
    expect(
      config.toolActions.geoCompass.modifiesMainParams
          ?.paramsFor('using', 'field_survey')
          .containsKey('discovery_chance'),
      isTrue,
    );
    expect(config.toolActions.geoCompass.modifiesMainParams?.owning, isEmpty);
    expect(
      config.toolActions.siteNavigator.modifiesMainParams
          ?.paramsFor('using', 'field_survey')
          .containsKey('discovery_chance'),
      isTrue,
    );
    expect(config.toolActions.geoCompass.durationMinutes, greaterThan(0));
    expect(config.toolActions.proximityScanner.discoveryChance, isNull);
    expect(
      config.toolActions.guidanceConfigFor('site_navigator').discoveryChance,
      isNotNull,
    );

    expect(config.toolActions.orbitSurvey.durationMinutes, greaterThan(0));
    expect(config.toolActions.orbitSurvey.resolvedRangeM, greaterThan(0));
    expect(
      config.toolActions.orbitSurvey.statsExplanation,
      contains('undiscovered field sites'),
    );
    expect(config.periodColors.orbitSurvey.jurassic.$1, isNonNegative);
    expect(config.periodColors.siteMarkers.cretaceous.$1, isNonNegative);

    expect(config.toolActions.formationMap.durationMinutes, greaterThan(0));
    expect(
      config.toolActions.formationMap.cellSizeM,
      config.siteGeneration.cellSizeM,
    );
    expect(config.rockTypeColors.forRockType('sandstone'), isNotNull);

    expect(config.toolActions.ridgeGlass.durationMinutes, greaterThan(0));
    expect(
      config.toolActions.ridgeGlass.siteDiscoveryMod('discovery_distance_m'),
      isNotNull,
    );
    expect(
      config.toolActions.ridgeGlass.siteDiscoveryMod('discovery_chance'),
      isNotNull,
    );
    expect(
      config.toolActions.ridgeGlass.siteDiscoveryMod('discovery_max_speed_kmh'),
      isNotNull,
    );
    expect(config.toolActions.ridgeGlass.addedDiscoveryDistanceM, isNull);
    expect(config.toolActions.ridgeGlass.addedDiscoveryRate, isNull);
    expect(
      config.toolActions.ridgeGlass.modifiesMainParams?.affectsSkill(
        'field_survey',
      ),
      isTrue,
    );

    for (final action in [
      config.toolActions.expeditionDrivetrain,
      config.toolActions.trailStriders,
      config.toolActions.canyonThrottle,
      config.toolActions.overlandChassis,
    ]) {
      expect(action.modifiesMainParams?.affectsSkill('field_survey'), isTrue);
      expect(
        action.modifiesMainParams
            ?.paramsFor('using', 'field_survey')
            .containsKey('documentation_distance_m'),
        isTrue,
      );
    }

    expect(config.toolActions.nocturneLens.durationMinutes, greaterThan(0));
    expect(config.toolActions.nocturneLens.activeWeatherTimes, ['night']);
    expect(
      config.toolActions.nocturneLens.siteDiscoveryMod('discovery_distance_m'),
      isNotNull,
    );
    expect(
      config.toolActions.nocturneLens.siteDiscoveryMod('discovery_chance'),
      isNotNull,
    );
    expect(
      config.toolActions.nocturneLens.siteDiscoveryMod(
        'discovery_max_speed_kmh',
      ),
      isNull,
    );

    expect(
      config.boneQuarry.mainParams.containsKey('locate_fossil_in_situ_xp'),
      isTrue,
    );
    expect(config.leveling.skills.length, 3);
    expect(config.leveling.careerTitles.length, 99);

    expect(GameConfig.isLoaded, isTrue);
    expect(
      GameConfig.instance.siteDiscovery.maxDistanceM,
      disc.discoveryDistanceM,
    );
  });

  test('instance throws before load', () {
    GameConfig.debugReset();
    expect(() => GameConfig.instance, throwsStateError);
  });
}
