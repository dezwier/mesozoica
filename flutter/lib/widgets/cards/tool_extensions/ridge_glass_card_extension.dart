import 'package:flutter/material.dart';

import '../../../models/ridge_glass_kind.dart';
import '../../../models/tool.dart';
import '../../tools/ridge_glass_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class RidgeGlassCardExtension implements ToolCardExtension {
  @override
  String get actionKey => RidgeGlassKind.actionKey;

  @override
  bool matches(ToolSummary tool) => RidgeGlassKind.matchesToolName(tool.name);

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
      child: RidgeGlassToolStats(params: params),
    );
  }
}
