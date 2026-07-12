import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';

class SiteCardHeader extends StatelessWidget {
  const SiteCardHeader({
    super.key,
    required this.site,
    this.titleFontSize = 28,
    this.subtitleFontSize = 10,
    this.centered = false,
    this.useFrontTitleStyle = false,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;
  final bool centered;
  final bool useFrontTitleStyle;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          site.displayTitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: useFrontTitleStyle
              ? cardTheme.frontTitleStyle(fontSize: titleFontSize)
              : cardTheme.titleStyle(fontSize: titleFontSize),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          site.displaySubtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: cardTheme.subtitleStyle(fontSize: subtitleFontSize).copyWith(
            color: cardTheme.cardTextMuted,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
