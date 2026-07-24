import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_mission_controller.dart';
import '../../models/aerial_mission_kind.dart';
import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../tools/aerial_mission_flight_stats.dart';
import '../tools/aerial_mission_actions.dart';
import '../tools/aerial_mission_missions_sheet.dart';
import 'card_section_panel.dart';

/// Per-action-key extras for tool card backs (stats, ongoing, info).
abstract class ToolCardExtension {
  String get actionKey;

  /// Whether this extension applies to [tool].
  bool matches(ToolSummary tool);

  Widget? buildDeployStats(BuildContext context, ToolSummary tool);

  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool);

  VoidCallback? infoHandler(BuildContext context, ToolSummary tool);
}

/// Registry of [ToolCardExtension]s keyed for lookup by tool.
class ToolCardExtensions {
  ToolCardExtensions._();

  static final List<ToolCardExtension> _all = [
    AerialMissionCardExtension(),
  ];

  static ToolCardExtension? forTool(ToolSummary tool) {
    for (final ext in _all) {
      if (ext.matches(tool)) return ext;
    }
    return null;
  }
}

class AerialMissionCardExtension implements ToolCardExtension {
  @override
  String get actionKey => 'aerial_mission';

  @override
  bool matches(ToolSummary tool) =>
      AerialMissionKind.tryParseToolName(tool.name) != null;

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final kind = AerialMissionKind.requireToolName(tool.name);
    return CardSectionPanel(
      child: AerialMissionFlightStats.fromConfig(actionKey: kind.actionKey),
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
    // Rebuild when poll updates discovered sites / remaining time.
    // ignore: unused_local_variable
    final _ = aerial.missionsFetchGeneration;
    // ignore: unused_local_variable
    final tick = aerial.progressTick;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AerialMissionSummaryLine(mission: mission),
          const SizedBox(height: 8),
          AerialMissionFlightStats.fromMission(mission),
          const SizedBox(height: 10),
          AerialMissionActions(mission: mission),
        ],
      ),
    );
  }
}
