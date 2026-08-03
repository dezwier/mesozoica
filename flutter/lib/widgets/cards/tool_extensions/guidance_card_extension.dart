import 'package:flutter/material.dart';

import '../../../models/guidance_tool_kind.dart';
import '../../../models/tool.dart';
import '../../tools/guidance_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class GuidanceCardExtension implements ToolCardExtension {
  @override
  String get actionKey => 'site_guidance';

  @override
  bool matches(ToolSummary tool) =>
      GuidanceToolKind.tryParseToolName(tool.name) != null;

  @override
  List<String> editableParamKeys(ToolSummary tool) {
    final guidance = GuidanceToolKind.requireToolName(tool.name);
    return switch (guidance) {
      GuidanceToolKind.geoCompass => const [
          'duration_minutes',
          'exactness',
        ],
      GuidanceToolKind.proximityScanner => const [
          'duration_minutes',
          'exactness',
        ],
      GuidanceToolKind.siteNavigator => const [
          'duration_minutes',
          'direction_exactness',
          'distance_exactness',
        ],
    };
  }

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final kind = GuidanceToolKind.requireToolName(tool.name);
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: GuidanceToolStats(actionKey: kind.actionKey, params: params),
    );
  }
}
