import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/aerial_mission_controller.dart';
import '../models/aerial_mission_kind.dart';
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tool.action} coming soon')),
    );
  }
}
