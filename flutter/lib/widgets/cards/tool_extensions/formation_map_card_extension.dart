import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/formation_map_controller.dart';
import '../../../models/formation_map_kind.dart';
import '../../../models/tool.dart';
import '../../tools/formation_map_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class FormationMapCardExtension implements ToolCardExtension {
  @override
  String get actionKey => FormationMapKind.actionKey;

  @override
  bool matches(ToolSummary tool) =>
      FormationMapKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'duration_minutes',
        'accuracy',
        'wideness_m',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: FormationMapToolStats(params: params),
    );
  }

  @override
  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return _FormationMapOngoingPanel(toolId: tool.id, toolParams: params);
  }
}

class _FormationMapOngoingPanel extends StatelessWidget {
  const _FormationMapOngoingPanel({
    required this.toolId,
    required this.toolParams,
  });

  final int toolId;
  final Map<String, dynamic> toolParams;

  @override
  Widget build(BuildContext context) {
    final formation = context.watch<FormationMapController>();
    if (!formation.isActive) return const SizedBox.shrink();
    final session = formation.session;
    if (session == null) return const SizedBox.shrink();
    if (session.toolId != toolId &&
        session.actionKey != FormationMapKind.actionKey) {
      return const SizedBox.shrink();
    }

    final sessionParams = <String, dynamic>{
      ...toolParams,
      'duration_minutes': session.durationMinutes,
      'accuracy': session.accuracy,
      'wideness_m': session.widenessM,
      'center_lat': session.centerLat,
      'center_lon': session.centerLon,
    };

    return CardSectionPanel(
      label: 'Active session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<Duration?>(
            valueListenable: formation.remainingListenable,
            builder: (context, remaining, _) {
              final minutes = remaining == null
                  ? '—'
                  : '${remaining.inMinutes.clamp(0, 999)} min left';
              return Text(
                minutes,
                style: Theme.of(context).textTheme.bodyMedium,
              );
            },
          ),
          const SizedBox(height: 8),
          FormationMapToolStats(params: sessionParams, compact: true),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => formation.stop(),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
