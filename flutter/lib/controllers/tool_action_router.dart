import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/aerial_mission_controller.dart';
import '../controllers/formation_map_controller.dart';
import '../controllers/orbit_survey_controller.dart';
import '../controllers/guidance_session_controller.dart';
import '../controllers/terrain_echo_controller.dart';
import '../models/aerial_mission_kind.dart';
import '../models/formation_map_kind.dart';
import '../models/orbit_survey_kind.dart';
import '../models/guidance_tool_kind.dart';
import '../models/terrain_echo_kind.dart';
import '../models/tool.dart';

typedef _ToolActivator = bool Function(BuildContext context, ToolSummary tool);

/// Dispatches tool-card action verbs to feature handlers.
class ToolActionRouter {
  const ToolActionRouter._();

  static final List<_ToolActivator> _activators = [
    _startAerial,
    _startGuidance,
    _startOrbitSurvey,
    _startFormationMap,
    _startTerrainEcho,
  ];

  static void start(BuildContext context, ToolSummary tool) {
    if (!tool.isOwned) return;

    for (final activator in _activators) {
      if (activator(context, tool)) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tool.action} coming soon')),
    );
  }

  static bool _startAerial(BuildContext context, ToolSummary tool) {
    if (AerialMissionKind.tryParseToolName(tool.name) == null) return false;
    context.read<AerialMissionController>().beginDraw(tool);
    return true;
  }

  static bool _startGuidance(BuildContext context, ToolSummary tool) {
    if (GuidanceToolKind.tryParseToolName(tool.name) == null) return false;
    context.read<OrbitSurveyController>().clearLocalSession();
    context.read<FormationMapController>().clearLocalSession();
    context.read<TerrainEchoController>().clearLocalSession();
    unawaited(context.read<GuidanceSessionController>().activate(tool));
    return true;
  }

  static bool _startOrbitSurvey(BuildContext context, ToolSummary tool) {
    if (!OrbitSurveyKind.matchesToolName(tool.name)) return false;
    context.read<GuidanceSessionController>().stop(notifyServer: false);
    context.read<FormationMapController>().clearLocalSession();
    context.read<TerrainEchoController>().clearLocalSession();
    unawaited(context.read<OrbitSurveyController>().activate(tool));
    return true;
  }

  static bool _startFormationMap(BuildContext context, ToolSummary tool) {
    if (!FormationMapKind.matchesToolName(tool.name)) return false;
    context.read<GuidanceSessionController>().stop(notifyServer: false);
    context.read<OrbitSurveyController>().clearLocalSession();
    context.read<TerrainEchoController>().clearLocalSession();
    unawaited(context.read<FormationMapController>().activate(tool));
    return true;
  }

  static bool _startTerrainEcho(BuildContext context, ToolSummary tool) {
    if (!TerrainEchoKind.matchesToolName(tool.name)) return false;
    context.read<GuidanceSessionController>().stop(notifyServer: false);
    context.read<OrbitSurveyController>().clearLocalSession();
    context.read<FormationMapController>().clearLocalSession();
    unawaited(context.read<TerrainEchoController>().activate(tool));
    return true;
  }
}
