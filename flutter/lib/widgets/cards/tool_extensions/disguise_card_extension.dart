import 'package:flutter/material.dart';

import '../../../models/disguise_tool_kind.dart';
import '../../../models/tool.dart';
import '../../tools/disguise_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class DisguiseCardExtension implements ToolCardExtension {
  @override
  String get actionKey => DisguiseToolKind.brushScrim.actionKey;

  @override
  bool matches(ToolSummary tool) =>
      DisguiseToolKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'duration_minutes',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final kind = DisguiseToolKind.tryParseToolName(tool.name);
    if (kind == null) return null;
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: DisguiseToolStats(kind: kind, params: params),
    );
  }
}
