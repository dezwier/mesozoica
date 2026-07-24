import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../controllers/tool_action_router.dart';
import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../tools/aerial_recon_flight_stats.dart';
import '../tools/aerial_recon_mission_actions.dart';
import '../tools/aerial_recon_missions_sheet.dart';
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
    AerialReconCardExtension(),
  ];

  static ToolCardExtension? forTool(ToolSummary tool) {
    for (final ext in _all) {
      if (ext.matches(tool)) return ext;
    }
    return null;
  }
}

class AerialReconCardExtension implements ToolCardExtension {
  @override
  String get actionKey => 'aerial_recon';

  @override
  bool matches(ToolSummary tool) =>
      tool.name == ToolActionRouter.aerialReconName;

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    return CardSectionPanel(
      child: AerialReconFlightStats.fromConfig(),
    );
  }

  @override
  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool) {
    return _AerialReconOngoingPanel(toolId: tool.id);
  }

  @override
  VoidCallback? infoHandler(BuildContext context, ToolSummary tool) {
    return () => AerialReconMissionsSheet.show(context);
  }
}

class _AerialReconOngoingPanel extends StatelessWidget {
  const _AerialReconOngoingPanel({required this.toolId});

  final int toolId;

  @override
  Widget build(BuildContext context) {
    final recon = context.watch<AerialReconController>();
    // Rebuild when poll updates discovered sites / remaining time.
    // ignore: unused_local_variable
    final _ = recon.missionsFetchGeneration;
    // ignore: unused_local_variable
    final tick = recon.progressTick;

    AerialReconMission? active;
    for (final m in recon.missions) {
      if (m.isActive && m.toolId == toolId) {
        active = m;
        break;
      }
    }
    if (active == null) {
      for (final m in recon.missions) {
        if (m.isActive) {
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
          AerialReconMissionSummaryLine(mission: mission),
          const SizedBox(height: 8),
          AerialReconFlightStats.fromMission(mission),
          const SizedBox(height: 10),
          AerialReconMissionActions(mission: mission),
        ],
      ),
    );
  }
}
