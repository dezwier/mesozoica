import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';

class FossilCardHeader extends StatelessWidget {
  const FossilCardHeader({
    super.key,
    required this.fossil,
    this.titleFontSize = 18,
    this.subtitleFontSize = 10,
    this.centered = false,
    this.useFrontTitleStyle = false,
    this.showOccurrenceSubtitle = false,
    this.wrapTitle = false,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;
  final bool showOccurrenceSubtitle;
  final bool wrapTitle;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          fossil.displayTitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: useFrontTitleStyle
              ? cardTheme.frontTitleStyle(fontSize: titleFontSize)
              : cardTheme.titleStyle(fontSize: titleFontSize),
          maxLines: wrapTitle ? null : 2,
          overflow: wrapTitle ? TextOverflow.visible : TextOverflow.ellipsis,
          softWrap: true,
        ),
        if (showOccurrenceSubtitle) ...[
          const SizedBox(height: 8),
          Text(
            'Occurrence No #${fossil.id}',
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: cardTheme.subtitleStyle(fontSize: subtitleFontSize).copyWith(
              color: cardTheme.cardTextMuted,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
