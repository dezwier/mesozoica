import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/aerial_session_controller.dart';
import '../../../models/aerial_action_kind.dart';
import '../../../models/tool.dart';
import '../../../models/tool_session.dart';
import '../../tools/aerial_session_actions.dart';
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
        'discovery_chance',
        'discovery_distance_m',
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

  @override
  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool) {
    final kind = AerialActionKind.requireToolName(tool.name);
    return _ToolSessionOngoingPanel(
      toolId: tool.id,
      actionKey: kind.actionKey,
    );
  }
}

class _ToolSessionOngoingPanel extends StatelessWidget {
  const _ToolSessionOngoingPanel({
    required this.toolId,
    required this.actionKey,
  });

  final int toolId;
  final String actionKey;

  @override
  Widget build(BuildContext context) {
    final aerial = context.watch<AerialSessionController>();

    ToolSession? active;
    for (final m in aerial.sessions) {
      if (m.isActive && m.toolId == toolId) {
        active = m;
        break;
      }
    }
    if (active == null) {
      for (final m in aerial.sessions) {
        if (m.isActive && m.actionKey == actionKey) {
          active = m;
          break;
        }
      }
    }
    if (active == null) return const SizedBox.shrink();

    final session = active;

    return CardSectionPanel(
      label: 'Ongoing flight',
      child: ListenableBuilder(
        listenable: aerial.progressTickListenable,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AerialSessionSummaryLine(session: session),
              const SizedBox(height: 8),
              AerialFlightStats.fromSession(session),
              const SizedBox(height: 10),
              AerialSessionActions(session: session),
            ],
          );
        },
      ),
    );
  }
}
