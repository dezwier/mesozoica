import 'package:flutter/material.dart';

import '../../../models/orbit_survey_kind.dart';
import '../../../models/tool.dart';
import '../../tools/orbit_survey_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class OrbitSurveyCardExtension implements ToolCardExtension {
  @override
  String get actionKey => OrbitSurveyKind.actionKey;

  @override
  bool matches(ToolSummary tool) => OrbitSurveyKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'duration_minutes',
        'accuracy',
        'range',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: OrbitSurveyToolStats(params: params),
    );
  }
}
