import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
import 'card_world_map.dart';
import 'geologic_timeline.dart';
import 'site_card_dimensions.dart';
import 'site_card_header.dart';
import 'site_card_image.dart';
import 'site_card_location_map.dart';
import 'site_card_related_lists.dart';
import 'site_card_user_timeline.dart';

class SiteCardBack extends StatelessWidget {
  const SiteCardBack({
    super.key,
    required this.site,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.mapTileLayerBuilder = CardWorldMap.defaultTileLayerBuilder,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;
  final Widget Function() mapTileLayerBuilder;

  static const _contentScale = 1.15;
  static const _bottomRowHeight = 78.0;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(
            image: SiteCardImage(imageUrl: site.mainImageUrl),
          ),
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
            top: 96,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardSectionPanel(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: SizedBox(
                    height: 70,
                    child: GeologicTimeline.fromAgeRange(
                      minAgeMa: site.minAgeMa,
                      maxAgeMa: site.maxAgeMa,
                      axis: GeologicTimelineAxis.horizontal,
                      scale: _contentScale,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SiteCardDimensions(site: site),
                const SizedBox(height: 6),
                SizedBox(
                  height: _bottomRowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: _bottomRowHeight,
                        child: CardSectionPanel(
                          padding: EdgeInsets.zero,
                          expandChild: true,
                          clipChild: true,
                          child: SiteCardLocationMap(
                            site: site,
                            tileLayerBuilder: mapTileLayerBuilder,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CardSectionPanel(
                          expandChild: true,
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                          child: SiteCardFossils(siteId: site.siteId),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SiteCardUserTimeline(site: site),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
