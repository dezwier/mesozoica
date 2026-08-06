import 'package:flutter/services.dart';

import '../domain/game_config.dart';

/// Flutter asset adapter for the otherwise platform-independent config model.
class GameConfigAssetLoader {
  const GameConfigAssetLoader._();

  static const _assetPrefix = 'assets/game_config';

  static Future<GameConfig> load() async {
    Future<String> read(String name) =>
        rootBundle.loadString('$_assetPrefix/$name');

    return GameConfig.loadFromYamlStrings(
      siteGenerationYaml: await read('site_generation.yaml'),
      fieldSurveyYaml: await read('01_field_survey.yaml'),
      boneQuarryYaml: await read('02_bone_quarry.yaml'),
      scienceHallYaml: await read('03_science_hall.yaml'),
      toolActionsYaml: await read('tool_actions.yaml'),
      periodColorsYaml: await read('period_colors.yaml'),
      rockTypeColorsYaml: await read('rock_type_colors.yaml'),
      levelingYaml: await read('leveling.yaml'),
    );
  }
}
