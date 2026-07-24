import 'package:flutter/material.dart';

import '../../models/tool.dart';
import '../../theme/dino_card_theme.dart';
import 'card_adaptive_title_text.dart';

class ToolCardHeader extends StatelessWidget {
  const ToolCardHeader({
    super.key,
    required this.tool,
    this.titleFontSize = 18,
    this.subtitleFontSize = 10,
    this.centered = false,
    this.overlayOnImage = false,
    this.showScientificSubtitle = false,
    this.subtitleOverride,
  });

  final ToolSummary tool;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool overlayOnImage;
  final bool showScientificSubtitle;
  /// When set, shown as the subtitle instead of scientific name.
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = overlayOnImage
        ? cardTheme.frontOverlayTitleStyle(fontSize: titleFontSize)
        : cardTheme.titleStyle(fontSize: titleFontSize);
    final subtitleStyle = overlayOnImage
        ? cardTheme.frontOverlaySubtitleStyle(fontSize: subtitleFontSize)
        : cardTheme.subtitleStyle(fontSize: subtitleFontSize).copyWith(
            color: cardTheme.cardTextMuted,
            fontWeight: FontWeight.w500,
          );

    final subtitle = subtitleOverride ??
        (showScientificSubtitle ? tool.scientificTool : null);

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (overlayOnImage && centered)
          SizedBox(
            width: double.infinity,
            child: CardAdaptiveTitleText(
              text: tool.name,
              style: titleStyle,
              textAlign: TextAlign.center,
            ),
          )
        else
          CardAdaptiveTitleText(
            text: tool.name,
            style: titleStyle,
          ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
        ],
      ],
    );
  }
}
