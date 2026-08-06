import 'package:flutter/material.dart';

import '../../../models/aerial_action_kind.dart';
import '../../../models/tool.dart';
import '../../tools/aerial_flight_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class AerialSessionCardExtension implements ToolCardExtension {
  @override
  String get actionKey => 'aerial';

  @override
  bool matches(ToolSummary tool) =>
      AerialActionKind.tryParseToolName(tool.name) != null;

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
    'flight_speed_kmh',
    'duration_minutes',
    'flight_discovery_chance',
    'flight_discovery_distance_m',
  ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final kind = AerialActionKind.requireToolName(tool.name);
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: params.isNotEmpty
          ? AerialFlightStats.fromParams(params)
          : AerialFlightStats.fromConfig(actionKey: kind.actionKey),
    );
  }
}
