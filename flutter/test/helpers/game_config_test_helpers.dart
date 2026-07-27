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
    siteDiscoveryYaml: read('site_discovery.yaml'),
    fossilGenerationYaml: read('fossil_generation.yaml'),
    fossilDiscoveryYaml: read('fossil_discovery.yaml'),
    fossilExcavationYaml: read('fossil_excavation.yaml'),
    toolActionsYaml: read('tool_actions.yaml'),
    levelingYaml: read('leveling.yaml'),
  );
}
