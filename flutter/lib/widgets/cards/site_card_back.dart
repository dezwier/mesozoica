import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'card_back_backdrop.dart';
import 'card_back_body.dart';
import 'card_back_corner_actions.dart';
import 'card_world_map.dart';
import 'geologic_timeline.dart';
import 'site_card_dimensions.dart';
import 'site_card_header.dart';
import 'site_card_image.dart';
import 'site_card_related_lists.dart';
import 'site_card_user_timeline.dart';

class SiteCardBack extends StatelessWidget {
  const SiteCardBack({
    super.key,
    required this.site,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.mapTileLayerBuilder = CardWorldMap.defaultTileLayerBuilder,
    this.onSiteUpdated,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;
  final Widget Function() mapTileLayerBuilder;
  final ValueChanged<SiteSummary>? onSiteUpdated;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final rockPart = site.rockType ?? site.siteTypeRockType ?? '';
    final rockText =
        rockPart.trim().isNotEmpty ? toTitleCase(rockPart.trim()) : '';
    final periodPart =
        site.titleIsRevealed ? site.displayPeriod : 'Age Hidden';
    final periodLine =
        rockText.isNotEmpty ? '$periodPart · $rockText' : periodPart;

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(image: SiteCardImage(imageUrl: site.mainImageUrl)),
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
              showSubtitle: false,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 72,
            bottom: 14,
            child: CardBackBody(
              children: [
                CardBackSection(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        periodLine,
                        textAlign: TextAlign.center,
                        style: cardTheme.bodyStyle(fontSize: 12.5).copyWith(
                              color: cardTheme.cardTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 48,
                        child: GeologicTimeline.fromAgeRange(
                          minAgeMa:
                              site.titleIsRevealed ? site.minAgeMa : null,
                          maxAgeMa:
                              site.titleIsRevealed ? site.maxAgeMa : null,
                          axis: GeologicTimelineAxis.horizontal,
                          scale: 1.0,
                          showYearLabels: true,
                        ),
                      ),
                    ],
                  ),
                ),
                SiteCardDimensions(site: site),
                CardBackSection(
                  title: 'Fossils',
                  child: SizedBox(
                    height: 72,
                    child: SiteCardFossils(
                      siteId: site.siteId,
                      thumbSize: 64,
                      tappable: true,
                      use2Rows: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
          CardBackCornerActions(
            onHistory: () => SiteCardUserTimeline.showDrawer(
              context,
              site: site,
            ),
          ),
        ],
      ),
    );
  }
}
