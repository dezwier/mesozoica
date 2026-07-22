import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'card_adaptive_title_text.dart';

class FossilCardHeader extends StatelessWidget {
  const FossilCardHeader({
    super.key,
    required this.fossil,
    this.titleFontSize = 18,
    this.subtitleFontSize = 10,
    this.centered = false,
    this.useFrontTitleStyle = false,
    this.overlayOnImage = false,
    this.showOccurrenceSubtitle = false,
    this.wrapTitle = false,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;
  final bool overlayOnImage;
  final bool showOccurrenceSubtitle;
  final bool wrapTitle;

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
        if (overlayOnImage && centered && !wrapTitle)
          SizedBox(
            width: double.infinity,
            child: CardAdaptiveTitleText(
              text: fossil.displayTitle,
              style: titleStyle,
              textAlign: TextAlign.center,
            ),
          )
        else if (overlayOnImage && !wrapTitle)
          CardAdaptiveTitleText(
            text: fossil.displayTitle,
            style: titleStyle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
          )
        else
          Text(
            fossil.displayTitle,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: titleStyle,
            maxLines: wrapTitle ? null : 2,
            overflow: wrapTitle ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: true,
          ),
        if (showOccurrenceSubtitle) ...[
          const SizedBox(height: 8),
          Text(
            fossil.displaySubtitle,
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
