import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../theme/dino_card_theme.dart';
import 'tool_card_back.dart';
import 'tool_card_front.dart';
import 'turnable_y_axis_card.dart';

class ToolTurnableCard extends StatelessWidget {
  const ToolTurnableCard({
    super.key,
    required this.tool,
    this.turnable = true,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
  });

  final ToolSummary tool;
  final bool turnable;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  Widget build(BuildContext context) {
    return TurnableYAxisCard(
      resetIdentity: tool.id,
      borderRadius: DinoCardTheme.borderRadius,
      outerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: DinoCardTheme.of(context).chromeDecoration(),
      turnable: turnable,
      front: ToolCardFront(
        tool: tool,
        titleFontSize: titleFontSize,
        subtitleFontSize: subtitleFontSize,
        overlayHeightFactor: overlayHeightFactor,
      ),
      back: ToolCardBack(
        tool: tool,
        titleFontSize: titleFontSize,
        subtitleFontSize: subtitleFontSize,
      ),
    );
  }
}
