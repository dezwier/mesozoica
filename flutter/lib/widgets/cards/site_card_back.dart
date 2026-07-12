import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'site_card_header.dart';
import 'site_card_image.dart';
import 'site_card_related_lists.dart';

class SiteCardBack extends StatelessWidget {
  const SiteCardBack({
    super.key,
    required this.site,
  });

  final SiteSummary site;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: cardTheme.cardBackground),
          Opacity(
            opacity: 0.1,
            child: SiteCardImage(imageUrl: site.mainImageUrl),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 30, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SiteCardHeader(
                  site: site,
                  titleFontSize: 28,
                  subtitleFontSize: 13,
                  centered: true,
                  useFrontTitleStyle: true,
                ),
                const SizedBox(height: 10),
                Text(
                  'FOSSIL RECORD',
                  textAlign: TextAlign.center,
                  style: cardTheme.sectionLabelStyle(fontSize: 11),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SiteCardFossils(siteId: site.siteId),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
