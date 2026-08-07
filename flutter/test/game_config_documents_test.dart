import 'package:flutter_test/flutter_test.dart';
import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/config/game_config_documents.dart';

import 'helpers/game_config_test_helpers.dart';

/// Dart mirror of the backend's JSON round-trip drift test.
///
/// The config API serves JSON-decoded maps, not `YamlMap`s. These tests pin
/// that every `fromYaml` factory parses both identically — in particular the
/// `fossil_count` integer keys, which JSON turns into strings.
void main() {
  tearDown(GameConfig.debugReset);

  test('document ids cover the whole control board', () {
    expect(kGameConfigDocumentFiles.length, 8);
    expect(kGameConfigDocumentIds.toSet().length, 8);
    expect(
      gameConfigDocumentsForTest().keys.toSet(),
      kGameConfigDocumentFiles.keys.toSet(),
    );
  });

  test('fromDocuments over JSON matches the YAML string loader', () async {
    final fromYaml = await loadGameConfigForTest();
    final fromJson = GameConfig.fromDocuments(gameConfigApiShapeForTest());

    expect(
      fromJson.siteGeneration.cellSizeM,
      fromYaml.siteGeneration.cellSizeM,
    );
    expect(
      fromJson.siteGeneration.client.nearbyRadiusKm,
      fromYaml.siteGeneration.client.nearbyRadiusKm,
    );

    expect(
      fromJson.siteDiscovery.visibilityDistanceM,
      fromYaml.siteDiscovery.visibilityDistanceM,
    );
    expect(
      fromJson.siteDiscovery.discoveryChance,
      fromYaml.siteDiscovery.discoveryChance,
    );
    expect(
      fromJson.siteDiscovery.discoverSiteXp,
      fromYaml.siteDiscovery.discoverSiteXp,
    );
    expect(
      fromJson.siteDiscovery.client.discoveryRerollIntervalS,
      fromYaml.siteDiscovery.client.discoveryRerollIntervalS,
    );

    // Weather modifier tables survive the round trip (nested maps + lists).
    final jsonNight = fromJson
        .siteDiscovery
        .weatherTimeModifiers['discover_site_xp']!['night']!;
    final yamlNight = fromYaml
        .siteDiscovery
        .weatherTimeModifiers['discover_site_xp']!['night']!;
    expect(jsonNight.length, yamlNight.length);
    expect(jsonNight.first.op, yamlNight.first.op);
    expect(jsonNight.first.value, yamlNight.first.value);

    // The int-key quirk: JSON stringifies these keys.
    expect(
      fromJson.siteStewardship.fossilCount,
      fromYaml.siteStewardship.fossilCount,
    );
    expect(fromJson.siteStewardship.fossilCount.keys, isNotEmpty);
    expect(
      fromJson.siteStewardship.levelModifiers['document_accuracy']!.length,
      fromYaml.siteStewardship.levelModifiers['document_accuracy']!.length,
    );

    expect(fromJson.leveling.skills.length, fromYaml.leveling.skills.length);
    expect(fromJson.leveling.careerTitles, fromYaml.leveling.careerTitles);
    expect(
      fromJson.periodColors.siteMarkers.cretaceous,
      fromYaml.periodColors.siteMarkers.cretaceous,
    );
    expect(
      fromJson.periodColors.orbitSurvey.triassic,
      fromYaml.periodColors.orbitSurvey.triassic,
    );
    expect(
      fromJson.rockTypeColors.formationMap,
      fromYaml.rockTypeColors.formationMap,
    );
  });

  test('fromDocuments does not set the singleton', () {
    GameConfig.fromDocuments(gameConfigApiShapeForTest());
    expect(GameConfig.isLoaded, isFalse);
  });

  test('fromDocuments rejects a missing document', () {
    final documents = gameConfigApiShapeForTest()..remove('leveling');
    expect(
      () => GameConfig.fromDocuments(documents),
      throwsA(isA<FormatException>()),
    );
  });
}
