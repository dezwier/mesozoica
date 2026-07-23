import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/aerial_recon_controller.dart';
import '../models/tool.dart';

/// Dispatches tool-card action verbs to feature handlers.
class ToolActionRouter {
  const ToolActionRouter._();

  static const aerialReconName = 'Aerial Recon';

  static void start(BuildContext context, ToolSummary tool) {
    if (!tool.isOwned) return;

    if (tool.name == aerialReconName) {
      context.read<AerialReconController>().beginDraw(tool);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tool.action} coming soon')),
    );
  }
}
