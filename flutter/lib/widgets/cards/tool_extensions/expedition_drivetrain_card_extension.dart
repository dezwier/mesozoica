import 'package:flutter/material.dart';

import '../../../models/expedition_drivetrain_kind.dart';
import '../../../models/tool.dart';
import '../../tools/expedition_drivetrain_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class ExpeditionDrivetrainCardExtension implements ToolCardExtension {
  @override
  String get actionKey => ExpeditionDrivetrainKind.actionKey;

  @override
  bool matches(ToolSummary tool) =>
      ExpeditionDrivetrainKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'duration_minutes',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: ExpeditionDrivetrainToolStats(params: params),
    );
  }
}
