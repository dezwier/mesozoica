import 'dart:convert';
import 'dart:io';

import 'package:mesozoica/config/game_config.dart';
import 'package:mesozoica/config/game_config_documents.dart';
import 'package:yaml/yaml.dart';

Directory _gameConfigDir() {
  final candidates = [
    Directory('assets/game_config'),
    Directory('../backend/app/game_config'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) return candidate;
  }
  throw StateError(
    'game_config directory not found. Expected assets/game_config symlink '
    'to backend/app/game_config',
  );
}

/// Raw YAML-decoded documents keyed by document id (the storage/wire shape).
Map<String, dynamic> gameConfigDocumentsForTest() {
  final dir = _gameConfigDir();
  return kGameConfigDocumentFiles.map(
    (id, filename) => MapEntry(
      id,
      loadYaml(File('${dir.path}/$filename').readAsStringSync()),
    ),
  );
}

/// The same documents as they arrive over the config API: JSON, not YamlMap.
///
/// Note this stringifies integer map keys (`fossil_count`) exactly as a real
/// JSON round trip through the database and API does.
Map<String, dynamic> gameConfigApiShapeForTest() {
  Object? toEncodable(Object? value) {
    if (value is YamlMap) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    if (value is YamlList) return value.toList();
    return value;
  }

  return jsonDecode(
    jsonEncode(gameConfigDocumentsForTest(), toEncodable: toEncodable),
  ) as Map<String, dynamic>;
}

/// Loads the shared YAML control board from the asset symlink (or backend path).
Future<GameConfig> loadGameConfigForTest() async {
  final dir = _gameConfigDir();

  String read(String name) => File('${dir.path}/$name').readAsStringSync();

  return GameConfig.loadFromYamlStrings(
    siteGenerationYaml: read('site_generation.yaml'),
    siteDiscoveryYaml: read('01_site_discovery.yaml'),
    siteStewardshipYaml: read('02_site_stewardship.yaml'),
    siteClearingYaml: read('03_site_clearing.yaml'),
    fossilDetectionYaml: read('04_fossil_detection.yaml'),
    fossilExcavationYaml: read('05_fossil_excavation.yaml'),
    fossilTransportYaml: read('06_fossil_transport.yaml'),
    fossilCurationYaml: read('07_fossil_curation.yaml'),
    fossilPreparationYaml: read('08_fossil_preparation.yaml'),
    fossilAnalysisYaml: read('09_fossil_analysis.yaml'),
    dinosaurModellingYaml: read('10_dinosaur_modelling.yaml'),
    dinosaurMountingYaml: read('11_dinosaur_mounting.yaml'),
    academicPublishingYaml: read('12_academic_publishing.yaml'),
    toolActionsYaml: read('tool_actions.yaml'),
    periodColorsYaml: read('period_colors.yaml'),
    rockTypeColorsYaml: read('rock_type_colors.yaml'),
    levelingYaml: read('leveling.yaml'),
  );
}
