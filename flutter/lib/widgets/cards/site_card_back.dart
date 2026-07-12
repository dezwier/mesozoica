import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'card_section_panel.dart';
import 'site_card_header.dart';
import 'site_card_image.dart';
import 'site_card_related_lists.dart';

class SiteCardBack extends StatelessWidget {
  const SiteCardBack({
    super.key,
    required this.site,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SiteCardImage(imageUrl: site.mainImageUrl),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: SiteCardHeader(
              site: site,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 72,
            bottom: 14,
            child: CardSectionPanel(
              label: 'Fossil record',
              expandChild: true,
              child: SiteCardFossils(siteId: site.siteId),
            ),
          ),
        ],
      ),
    );
  }
}
