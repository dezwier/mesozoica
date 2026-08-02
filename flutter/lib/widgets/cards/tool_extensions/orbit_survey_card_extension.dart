import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/orbit_survey_controller.dart';
import '../../../models/orbit_survey_kind.dart';
import '../../../models/tool.dart';
import '../../tools/orbit_survey_tool_stats.dart';
import '../card_section_panel.dart';
import '../tool_card_extension.dart';

class OrbitSurveyCardExtension implements ToolCardExtension {
  @override
  String get actionKey => OrbitSurveyKind.actionKey;

  @override
  bool matches(ToolSummary tool) => OrbitSurveyKind.matchesToolName(tool.name);

  @override
  List<String> editableParamKeys(ToolSummary tool) => const [
        'duration_minutes',
        'accuracy',
        'range',
      ];

  @override
  Widget? buildDeployStats(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return CardSectionPanel(
      child: OrbitSurveyToolStats(params: params),
    );
  }

  @override
  Widget? buildOngoingPanel(BuildContext context, ToolSummary tool) {
    final params = tool.isOwned && tool.params.isNotEmpty
        ? tool.params
        : tool.baseParams;
    return _OrbitSurveyOngoingPanel(toolId: tool.id, toolParams: params);
  }

  @override
  VoidCallback? infoHandler(BuildContext context, ToolSummary tool) => null;
}

class _OrbitSurveyOngoingPanel extends StatelessWidget {
  const _OrbitSurveyOngoingPanel({
    required this.toolId,
    required this.toolParams,
  });

  final int toolId;
  final Map<String, dynamic> toolParams;

  @override
  Widget build(BuildContext context) {
    final survey = context.watch<OrbitSurveyController>();
    if (!survey.isActive) return const SizedBox.shrink();
    final session = survey.session;
    if (session == null) return const SizedBox.shrink();
    if (session.toolId != toolId &&
        session.actionKey != OrbitSurveyKind.actionKey) {
      return const SizedBox.shrink();
    }

    final sessionParams = <String, dynamic>{
      ...toolParams,
      'duration_minutes': session.durationMinutes,
      'accuracy': session.accuracy,
      'range': session.range,
      'min_range_m': session.minRangeM,
      'max_range_m': session.maxRangeM,
    };

    return CardSectionPanel(
      label: 'Active session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<Duration?>(
            valueListenable: survey.remainingListenable,
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
          OrbitSurveyToolStats(params: sessionParams, compact: true),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => survey.stop(),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
