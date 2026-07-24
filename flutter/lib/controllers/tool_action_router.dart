import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/aerial_mission_controller.dart';
import '../controllers/guidance_session_controller.dart';
import '../models/aerial_mission_kind.dart';
import '../models/guidance_tool_kind.dart';
import '../models/tool.dart';

/// Dispatches tool-card action verbs to feature handlers.
class ToolActionRouter {
  const ToolActionRouter._();

  static void start(BuildContext context, ToolSummary tool) {
    if (!tool.isOwned) return;

    if (AerialMissionKind.tryParseToolName(tool.name) != null) {
      context.read<AerialMissionController>().beginDraw(tool);
      return;
    }

    if (GuidanceToolKind.tryParseToolName(tool.name) != null) {
      unawaited(context.read<GuidanceSessionController>().activate(tool));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tool.action} coming soon')),
    );
  }
}
