import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'card_adaptive_title_text.dart';

class SiteCardHeader extends StatelessWidget {
  const SiteCardHeader({
    super.key,
    required this.site,
    this.titleFontSize = 28,
    this.subtitleFontSize = 10,
    this.centered = false,
    this.useFrontTitleStyle = false,
    this.overlayOnImage = false,
    this.showSubtitle = true,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;
  final bool overlayOnImage;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = overlayOnImage
        ? cardTheme.frontOverlayTitleStyle(fontSize: titleFontSize)
        : useFrontTitleStyle
            ? cardTheme.frontTitleStyle(fontSize: titleFontSize)
            : cardTheme.titleStyle(fontSize: titleFontSize);
    final subtitleStyle = overlayOnImage
        ? cardTheme.frontOverlaySubtitleStyle(fontSize: subtitleFontSize)
        : cardTheme.subtitleStyle(fontSize: subtitleFontSize).copyWith(
            color: cardTheme.cardTextMuted,
            fontWeight: FontWeight.w500,
          );

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (overlayOnImage && centered)
          SizedBox(
            width: double.infinity,
            child: CardAdaptiveTitleText(
              text: site.displayTitle,
              style: titleStyle,
              textAlign: TextAlign.center,
            ),
          )
        else
          overlayOnImage
              ? CardAdaptiveTitleText(
                  text: site.displayTitle,
                  style: titleStyle,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                )
              : Text(
                  site.displayTitle,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: titleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        if (showSubtitle) ...[
          const SizedBox(height: 8),
          Text(
            site.displaySubtitle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: subtitleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
