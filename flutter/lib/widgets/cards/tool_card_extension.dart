import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/aerial_mission_controller.dart';
import '../../controllers/formation_map_controller.dart';
import '../../controllers/orbit_survey_controller.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../models/aerial_mission_kind.dart';
import '../../models/formation_map_kind.dart';
import '../../models/orbit_survey_kind.dart';
import '../../models/guidance_tool_kind.dart';
import '../../models/tool.dart';
import '../../services/tool_service.dart';
import '../tools/aerial_mission_flight_stats.dart';
import '../tools/aerial_mission_actions.dart';
import '../tools/aerial_mission_missions_sheet.dart';
import '../tools/formation_map_tool_stats.dart';
import '../tools/orbit_survey_tool_stats.dart';
import '../tools/guidance_tool_stats.dart';
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
    GuidanceCardExtension(),
    OrbitSurveyCardExtension(),
    FormationMapCardExtension(),
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

class GuidanceCardExtension implements ToolCardExtension {
  @override
  String get actionKey => 'site_guidance';

  @override
  bool matches(ToolSummary tool) =>
      GuidanceToolKind.tryParseToolName(tool.name) != null;

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

  @override
  VoidCallback? infoHandler(BuildContext context, ToolSummary tool) => null;
}

class OrbitSurveyCardExtension implements ToolCardExtension {
  @override
  String get actionKey => OrbitSurveyKind.actionKey;

  @override
  bool matches(ToolSummary tool) =>
      OrbitSurveyKind.matchesToolName(tool.name);

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


class FormationMapCardExtension implements ToolCardExtension {
  @override
  String get actionKey => FormationMapKind.actionKey;

  @override
  bool matches(ToolSummary tool) =>
      FormationMapKind.matchesToolName(tool.name);

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

  @override
  VoidCallback? infoHandler(BuildContext context, ToolSummary tool) => null;
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

    // Prefer the snapshotted session knobs (what the action actually used),
    // falling back to the tool-instance params for any missing fields.
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

class _OrbitSurveyOngoingPanel extends StatelessWidget {
  const _OrbitSurveyOngoingPanel({
    required this.toolId,
    required this.toolParams,
  });

  final int toolId;
  final Map<String, dynamic> toolParams;

  @override
  Widget build(BuildContext context) {
    final formation = context.watch<OrbitSurveyController>();
    if (!formation.isActive) return const SizedBox.shrink();
    final session = formation.session;
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
          OrbitSurveyToolStats(params: sessionParams, compact: true),
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
