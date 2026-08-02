import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/guidance_session_controller.dart';
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
          'discovery_chance',
        ],
      GuidanceToolKind.proximityScanner => const [
          'duration_minutes',
          'exactness',
        ],
      GuidanceToolKind.siteNavigator => const [
          'duration_minutes',
          'direction_exactness',
          'distance_exactness',
          'discovery_chance',
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

  @override
  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool) {
    final kind = GuidanceToolKind.requireToolName(tool.name);
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return _GuidanceOngoingPanel(
      toolId: tool.id,
      actionKey: kind.actionKey,
      toolParams: params,
    );
  }
}

class _GuidanceOngoingPanel extends StatelessWidget {
  const _GuidanceOngoingPanel({
    required this.toolId,
    required this.actionKey,
    required this.toolParams,
  });

  final int toolId;
  final String actionKey;
  final Map<String, dynamic> toolParams;

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceSessionController>();
    if (!guidance.isActive) return const SizedBox.shrink();
    final session = guidance.session;
    if (session == null) return const SizedBox.shrink();
    if (session.toolId != toolId && session.actionKey != actionKey) {
      return const SizedBox.shrink();
    }

    final sessionParams = <String, dynamic>{
      ...toolParams,
      'duration_minutes': session.durationMinutes,
      if (session.discoveryChance != null)
        'discovery_chance': session.discoveryChance,
      if (session.directionExactness != null)
        'direction_exactness': session.directionExactness,
      if (session.distanceExactness != null)
        'distance_exactness': session.distanceExactness,
    };

    return CardSectionPanel(
      label: 'Active session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<Duration?>(
            valueListenable: guidance.remainingListenable,
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
          GuidanceToolStats(
            actionKey: session.actionKey,
            params: sessionParams,
            compact: true,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => guidance.stop(),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
