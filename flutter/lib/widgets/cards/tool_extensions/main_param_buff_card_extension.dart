import 'package:flutter/material.dart';

import '../../../config/game_config.dart';
import '../../../config/tool_instance_params.dart';
import '../../../models/main_param_buff_kind.dart';
import '../../../models/tool.dart';
import '../../tools/main_param_buff_tool_stats.dart';
import '../tool_card_extension.dart';

/// Shared card-back extension for Ridge Glass / Drivetrain / Nocturne Lens.
class MainParamBuffCardExtension extends ToolCardExtension {
  @override
  String get actionKey => 'main_param_buff';

  @override
  bool matches(ToolSummary tool) =>
      MainParamBuffKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'duration_minutes',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final kind = MainParamBuffKind.tryParseToolName(tool.name);
    final cfg = switch (kind?.actionKey) {
      'expedition_drivetrain' =>
        GameConfig.instance.toolActions.expeditionDrivetrain,
      'nocturne_lens' => GameConfig.instance.toolActions.nocturneLens,
      _ => GameConfig.instance.toolActions.ridgeGlass,
    };
    final params = ownedToolInstanceParams(tool);
    return MainParamBuffToolStats(
      params: params.isEmpty ? cfg.toParamsJson() : params,
      yamlFallback: cfg.toParamsJson(),
    );
  }
}
