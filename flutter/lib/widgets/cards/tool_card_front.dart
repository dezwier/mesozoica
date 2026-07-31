import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../theme/dino_card_theme.dart';
import 'occurrence_id_badge.dart';
import 'tool_card_header.dart';
import 'tool_card_image.dart';

class ToolCardFront extends StatelessWidget {
  const ToolCardFront({
    super.key,
    required this.tool,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
  });

  final ToolSummary tool;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final description = tool.description.trim().isNotEmpty
        ? tool.description.trim()
        : '—';
    final showIdBadge = tool.isToolInstance;

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ToolCardImage(imageUrl: tool.mainImageUrl),
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: overlayHeightFactor,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: cardTheme.frontOverlayGradient(),
                  ),
                ),
              ),
            ),
          ),
          if (showIdBadge)
            Positioned(
              top: 14,
              left: 14,
              child: OccurrenceIdBadge(label: tool.occurrenceIdBadgeLabel),
            ),
          Positioned(
            left: 18,
            right: 18,
            bottom: math.max(16, titleFontSize * 0.45),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ToolCardHeader(
                  tool: tool,
                  titleFontSize: titleFontSize,
                  subtitleFontSize: subtitleFontSize,
                  centered: true,
                  overlayOnImage: true,
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: cardTheme.frontOverlayBodyStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
