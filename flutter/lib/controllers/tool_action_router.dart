import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/aerial_session_controller.dart';
import '../controllers/disguise_session_controller.dart';
import '../controllers/formation_map_controller.dart';
import '../controllers/orbit_survey_controller.dart';
import '../controllers/guidance_session_controller.dart';
import '../controllers/main_param_buff_controller.dart';
import '../controllers/terrain_echo_controller.dart';
import '../models/aerial_action_kind.dart';
import '../models/disguise_tool_kind.dart';
import '../models/formation_map_kind.dart';
import '../models/orbit_survey_kind.dart';
import '../models/guidance_tool_kind.dart';
import '../models/main_param_buff_kind.dart';
import '../models/terrain_echo_kind.dart';
import '../models/tool.dart';
import '../models/tool_session.dart';
import '../services/location_service.dart';
import '../widgets/common/app_toast.dart';

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
    _startMainParamBuff,
    _startDisguise,
  ];

  static void start(BuildContext context, ToolSummary tool) {
    if (!tool.isOwned) return;

    final blocking = cardInUseLabel(context, forTool: tool);
    if (blocking != null) {
      AppToast.warning(context, '$blocking is already in use');
      return;
    }

    for (final activator in _activators) {
      if (activator(context, tool)) return;
    }

    AppToast.info(context, '${tool.action} coming soon');
  }

  /// Display name of a live tool card that blocks starting [forTool], if any.
  ///
  /// Includes the same card when it already has a live session / draw.
  /// Disguise → disguise is allowed (server replaces the prior cover).
  static String? cardInUseLabel(
    BuildContext context, {
    required ToolSummary forTool,
  }) {
    final aerial = context.read<AerialSessionController>();
    if (aerial.isDrawMode) {
      final drawTool = aerial.tool;
      if (drawTool != null) return drawTool.name;
    }
    for (final session in aerial.sessions) {
      if (!session.isActive) continue;
      return _labelForSession(session) ?? forTool.name;
    }

    final guidance = context.read<GuidanceSessionController>();
    if (guidance.isActive) {
      return guidance.kind?.toolName ??
          guidance.tool?.name ??
          _labelForSession(guidance.session) ??
          'Guidance tool';
    }

    final orbit = context.read<OrbitSurveyController>();
    if (orbit.isActive) {
      return orbit.tool?.name ?? OrbitSurveyKind.toolName;
    }

    final formation = context.read<FormationMapController>();
    if (formation.isActive) {
      return formation.tool?.name ?? FormationMapKind.toolName;
    }

    final terrain = context.read<TerrainEchoController>();
    if (terrain.isActive) {
      return terrain.tool?.name ?? TerrainEchoKind.toolName;
    }

    final buff = context.read<MainParamBuffController>();
    if (buff.isActive) {
      return buff.tool?.name ?? buff.kind?.toolName ?? 'Buff tool';
    }

    final disguise = context.read<DisguiseSessionController>();
    if (disguise.isPickMode || disguise.isActive) {
      if (DisguiseToolKind.matchesToolName(forTool.name)) {
        return null;
      }
      return disguise.tool?.name ??
          disguise.kind?.toolName ??
          _labelForSession(disguise.session) ??
          'Disguise tool';
    }

    return null;
  }

  static String? _labelForSession(ToolSession? session) {
    if (session == null) return null;
    return AerialActionKind.tryParseActionKey(session.actionKey)?.toolName ??
        GuidanceToolKind.tryParseActionKey(session.actionKey)?.toolName ??
        (session.actionKey == OrbitSurveyKind.actionKey
            ? OrbitSurveyKind.toolName
            : null) ??
        (session.actionKey == FormationMapKind.actionKey
            ? FormationMapKind.toolName
            : null) ??
        (session.actionKey == TerrainEchoKind.actionKey
            ? TerrainEchoKind.toolName
            : null) ??
        (MainParamBuffKind.tryParseActionKey(session.actionKey)?.toolName) ??
        DisguiseToolKind.tryParseActionKey(session.actionKey)?.toolName;
  }

  static bool _startAerial(BuildContext context, ToolSummary tool) {
    if (AerialActionKind.tryParseToolName(tool.name) == null) return false;
    context.read<AerialSessionController>().beginDraw(tool);
    return true;
  }

  static bool _startGuidance(BuildContext context, ToolSummary tool) {
    if (GuidanceToolKind.tryParseToolName(tool.name) == null) return false;
    unawaited(context.read<GuidanceSessionController>().activate(tool));
    return true;
  }

  static bool _startOrbitSurvey(BuildContext context, ToolSummary tool) {
    if (!OrbitSurveyKind.matchesToolName(tool.name)) return false;
    unawaited(context.read<OrbitSurveyController>().activate(tool));
    return true;
  }

  static bool _startFormationMap(BuildContext context, ToolSummary tool) {
    if (!FormationMapKind.matchesToolName(tool.name)) return false;
    unawaited(context.read<FormationMapController>().activate(tool));
    return true;
  }

  static bool _startTerrainEcho(BuildContext context, ToolSummary tool) {
    if (!TerrainEchoKind.matchesToolName(tool.name)) return false;
    unawaited(context.read<TerrainEchoController>().activate(tool));
    return true;
  }

  static bool _startMainParamBuff(BuildContext context, ToolSummary tool) {
    if (!MainParamBuffKind.matchesToolName(tool.name)) return false;
    final loc = context.read<LocationService>().currentLocation;
    unawaited(
      context.read<MainParamBuffController>().activate(
        tool,
        lat: loc?.latitude,
        lon: loc?.longitude,
      ),
    );
    return true;
  }

  static bool _startDisguise(BuildContext context, ToolSummary tool) {
    if (!DisguiseToolKind.matchesToolName(tool.name)) return false;
    context.read<DisguiseSessionController>().beginPick(tool);
    return true;
  }
}
