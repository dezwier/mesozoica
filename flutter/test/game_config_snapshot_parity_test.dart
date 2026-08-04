import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';

import 'helpers/game_config_test_helpers.dart';

/// Loads the bundled canonical snapshot (`assets/game_config.json`) the way the
/// client would, via [GameConfig.fromSections].
GameConfig _loadSnapshot() {
  final file = File('assets/game_config.json');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Missing assets/game_config.json — regenerate with '
        '`cd backend && .venv/bin/python -m scripts.export_bundled_game_config`',
  );
  final document = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return GameConfig.fromSections(document['config'] as Map<String, dynamic>);
}

void main() {
  tearDown(GameConfig.debugReset);

  test('bundled canonical snapshot parses into every section', () {
    final cfg = _loadSnapshot();

    // Scalars / nested objects across every domain must be present & sane.
    expect(cfg.siteGeneration.cellSizeM, greaterThan(0));
    expect(cfg.siteGeneration.client.nearbyRadiusKm, greaterThan(0));
    expect(cfg.siteDiscovery.discoveryChance, inInclusiveRange(0.0, 1.0));
    expect(cfg.siteDiscovery.client.discoveryRerollIntervalS, greaterThan(0));
    expect(cfg.siteStewardship.mainParams.siteVisibilityM, greaterThan(0));
    expect(cfg.siteStewardship.dinoCount, isNotEmpty);
    expect(cfg.siteStewardship.accuracyNoise.maxDelta, greaterThanOrEqualTo(0));
    expect(cfg.leveling.skills, isNotEmpty);
    expect(cfg.leveling.careerTitles, isNotEmpty);
    expect(cfg.toolActions.aerialRecon.flightSpeedKmh, greaterThan(0));
    expect(cfg.toolActions.orbitSurvey.resolvedRangeM, greaterThan(0));
    expect(cfg.periodColors.siteMarkers.forPeriod('jurassic'), isA<(int, int, int)>());
    expect(cfg.rockTypeColors.forRockType('sandstone'), isA<(int, int, int)>());
  });

  test('canonical snapshot equals the YAML control-board projection', () async {
    final snapshot = _loadSnapshot();
    GameConfig.debugReset();
    final yaml = await loadGameConfigForTest();

    // Site discovery
    expect(snapshot.siteDiscovery.discoveryChance, yaml.siteDiscovery.discoveryChance);
    expect(snapshot.siteDiscovery.visibilityDistanceM, yaml.siteDiscovery.visibilityDistanceM);
    expect(snapshot.siteDiscovery.maxDiscoverySpeedKmh, yaml.siteDiscovery.maxDiscoverySpeedKmh);
    expect(snapshot.siteDiscovery.siteDiscoveryXp, yaml.siteDiscovery.siteDiscoveryXp);
    expect(snapshot.siteDiscovery.activeKmXp, yaml.siteDiscovery.activeKmXp);
    expect(snapshot.siteDiscovery.client.autoDiscoverRadiusM, yaml.siteDiscovery.client.autoDiscoverRadiusM);
    expect(snapshot.siteDiscovery.client.cacheRadiusKm, yaml.siteDiscovery.client.cacheRadiusKm);

    // Site generation
    expect(snapshot.siteGeneration.cellSizeM, yaml.siteGeneration.cellSizeM);
    expect(snapshot.siteGeneration.client.nearbyRadiusKm, yaml.siteGeneration.client.nearbyRadiusKm);

    // Site stewardship
    expect(snapshot.siteStewardship.mainParams.siteVisibilityM, yaml.siteStewardship.mainParams.siteVisibilityM);
    expect(snapshot.siteStewardship.dinoCount.length, yaml.siteStewardship.dinoCount.length);
    expect(snapshot.siteStewardship.accuracyNoise.maxDelta, yaml.siteStewardship.accuracyNoise.maxDelta);
    expect(snapshot.siteStewardship.oddNoise.dinoCount, yaml.siteStewardship.oddNoise.dinoCount);

    // Leveling
    expect(snapshot.leveling.skills.length, yaml.leveling.skills.length);
    expect(snapshot.leveling.skills.first.id, yaml.leveling.skills.first.id);
    expect(snapshot.leveling.careerTitles.length, yaml.leveling.careerTitles.length);

    // Tool actions
    expect(snapshot.toolActions.aerialRecon.flightSpeedKmh, yaml.toolActions.aerialRecon.flightSpeedKmh);
    expect(snapshot.toolActions.orbitSurvey.resolvedRangeM, yaml.toolActions.orbitSurvey.resolvedRangeM);
    expect(
      snapshot.toolActions.guidanceConfigFor('geo_compass').discoveryChance,
      yaml.toolActions.guidanceConfigFor('geo_compass').discoveryChance,
    );

    // Palettes
    expect(snapshot.periodColors.siteMarkers.forPeriod('jurassic'),
        yaml.periodColors.siteMarkers.forPeriod('jurassic'));
    expect(snapshot.rockTypeColors.forRockType('sandstone'),
        yaml.rockTypeColors.forRockType('sandstone'));
  });
}
