import 'package:flutter/material.dart';

import '../../../models/formation_map_kind.dart';
import '../../../models/tool.dart';
import '../../tools/formation_map_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class FormationMapCardExtension implements ToolCardExtension {
  @override
  String get actionKey => FormationMapKind.actionKey;

  @override
  bool matches(ToolSummary tool) => FormationMapKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
    'duration_minutes',
    'accuracy',
    'wideness_m',
  ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(child: FormationMapToolStats(params: params));
  }
}
