import 'package:flutter/material.dart';

import '../../models/tool.dart';
import 'tool_extensions/aerial_session_card_extension.dart';
import 'tool_extensions/disguise_card_extension.dart';
import 'tool_extensions/formation_map_card_extension.dart';
import 'tool_extensions/guidance_card_extension.dart';
import 'tool_extensions/main_param_buff_card_extension.dart';
import 'tool_extensions/orbit_survey_card_extension.dart';
import 'tool_extensions/terrain_echo_card_extension.dart';

/// Per-action-key extras for tool card backs (stats, params).
abstract class ToolCardExtension {
  String get actionKey;

  /// Whether this extension applies to [tool].
  bool matches(ToolSummary tool);

  /// Param keys shown in the inventory edit sheet for this tool.
  List<String> editableParamKeys(ToolSummary tool);

  Widget? buildDeployStats(BuildContext context, ToolSummary tool);
}

/// Registry of [ToolCardExtension]s keyed for lookup by tool.
class ToolCardExtensions {
  ToolCardExtensions._();

  static final List<ToolCardExtension> _all = [
    AerialSessionCardExtension(),
    GuidanceCardExtension(),
    OrbitSurveyCardExtension(),
    FormationMapCardExtension(),
    TerrainEchoCardExtension(),
    MainParamBuffCardExtension(),
    DisguiseCardExtension(),
  ];

  static ToolCardExtension? forTool(ToolSummary tool) {
    for (final ext in _all) {
      if (ext.matches(tool)) return ext;
    }
    return null;
  }
}
