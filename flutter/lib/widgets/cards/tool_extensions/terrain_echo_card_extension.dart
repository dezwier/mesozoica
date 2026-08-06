import 'package:flutter/material.dart';

import '../../../models/terrain_echo_kind.dart';
import '../../../models/tool.dart';
import '../../tools/terrain_echo_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class TerrainEchoCardExtension implements ToolCardExtension {
  @override
  String get actionKey => TerrainEchoKind.actionKey;

  @override
  bool matches(ToolSummary tool) => TerrainEchoKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
    'duration_minutes',
    'accuracy',
    'range_m',
  ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(child: TerrainEchoToolStats(params: params));
  }
}
