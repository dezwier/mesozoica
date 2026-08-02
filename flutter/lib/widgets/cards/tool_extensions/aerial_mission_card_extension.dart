import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/aerial_mission_controller.dart';
import '../../../models/aerial_mission_kind.dart';
import '../../../models/tool.dart';
import '../../../services/tool_service.dart';
import '../../tools/aerial_mission_actions.dart';
import '../../tools/aerial_mission_flight_stats.dart';
import '../../tools/aerial_mission_missions_sheet.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class AerialMissionCardExtension implements ToolCardExtension {
  @override
  String get actionKey => 'aerial_mission';

  @override
  bool matches(ToolSummary tool) =>
      AerialMissionKind.tryParseToolName(tool.name) != null;

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'flight_speed_kmh',
        'max_route_km',
        'discovery_chance',
        'discovery_distance_m',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final kind = AerialMissionKind.requireToolName(tool.name);
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: params.isNotEmpty
          ? AerialMissionFlightStats.fromParams(params)
          : AerialMissionFlightStats.fromConfig(actionKey: kind.actionKey),
    );
  }

  @override
  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool) {
    final kind = AerialMissionKind.requireToolName(tool.name);
    return _AerialMissionOngoingPanel(
      toolId: tool.id,
      actionKey: kind.actionKey,
    );
  }

  @override
  VoidCallback? infoHandler(BuildContext context, ToolSummary tool) {
    final kind = AerialMissionKind.requireToolName(tool.name);
    return () => AerialMissionsSheet.show(context, kind: kind);
  }
}

class _AerialMissionOngoingPanel extends StatelessWidget {
  const _AerialMissionOngoingPanel({
    required this.toolId,
    required this.actionKey,
  });

  final int toolId;
  final String actionKey;

  @override
  Widget build(BuildContext context) {
    final aerial = context.watch<AerialMissionController>();

    AerialMission? active;
    for (final m in aerial.missions) {
      if (m.isActive && m.toolId == toolId) {
        active = m;
        break;
      }
    }
    if (active == null) {
      for (final m in aerial.missions) {
        if (m.isActive && m.actionKey == actionKey) {
          active = m;
          break;
        }
      }
    }
    if (active == null) return const SizedBox.shrink();

    final mission = active;

    return CardSectionPanel(
      label: 'Ongoing flight',
      child: ListenableBuilder(
        listenable: aerial.progressTickListenable,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AerialMissionSummaryLine(mission: mission),
              const SizedBox(height: 8),
              AerialMissionFlightStats.fromMission(mission),
              const SizedBox(height: 10),
              AerialMissionActions(mission: mission),
            ],
          );
        },
      ),
    );
  }
}
