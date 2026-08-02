import 'dart:io';

import 'package:mesozoica/config/game_config.dart';

/// Loads the shared YAML control board from the asset symlink (or backend path).
Future<GameConfig> loadGameConfigForTest() async {
  final candidates = [
    Directory('assets/game_config'),
    Directory('../backend/app/game_config'),
  ];
  Directory? dir;
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      dir = candidate;
      break;
    }
  }
  if (dir == null) {
    throw StateError(
      'game_config directory not found. Expected assets/game_config symlink '
      'to backend/app/game_config',
    );
  }

  String read(String name) => File('${dir!.path}/$name').readAsStringSync();

  return GameConfig.loadFromYamlStrings(
    siteGenerationYaml: read('site_generation.yaml'),
    siteDiscoveryYaml: read('01_site_discovery.yaml'),
    siteSurveyYaml: read('02_site_survey.yaml'),
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
