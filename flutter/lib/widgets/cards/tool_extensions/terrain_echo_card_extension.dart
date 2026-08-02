import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/terrain_echo_controller.dart';
import '../../../models/terrain_echo_kind.dart';
import '../../../models/tool.dart';
import '../../tools/terrain_echo_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class TerrainEchoCardExtension implements ToolCardExtension {
  @override
  String get actionKey => TerrainEchoKind.actionKey;

  @override
  bool matches(ToolSummary tool) => TerrainEchoKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'duration_minutes',
        'accuracy',
        'range_m',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: TerrainEchoToolStats(params: params),
    );
  }

  @override
  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return _TerrainEchoOngoingPanel(toolId: tool.id, toolParams: params);
  }

  @override
  VoidCallback? infoHandler(BuildContext context, ToolSummary tool) => null;
}

class _TerrainEchoOngoingPanel extends StatelessWidget {
  const _TerrainEchoOngoingPanel({
    required this.toolId,
    required this.toolParams,
  });

  final int toolId;
  final Map<String, dynamic> toolParams;

  @override
  Widget build(BuildContext context) {
    final echo = context.watch<TerrainEchoController>();
    if (!echo.isActive) return const SizedBox.shrink();
    final session = echo.session;
    if (session == null) return const SizedBox.shrink();
    if (session.toolId != toolId &&
        session.actionKey != TerrainEchoKind.actionKey) {
      return const SizedBox.shrink();
    }

    final sessionParams = <String, dynamic>{
      ...toolParams,
      'duration_minutes': session.durationMinutes,
      'accuracy': session.accuracy,
      'range_m': session.rangeM,
    };

    return CardSectionPanel(
      label: 'Active session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<Duration?>(
            valueListenable: echo.remainingListenable,
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
          TerrainEchoToolStats(params: sessionParams, compact: true),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => echo.stop(),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
