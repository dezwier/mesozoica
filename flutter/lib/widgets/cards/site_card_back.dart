import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../utils/display_text.dart';
import 'card_back_body.dart';
import 'card_world_map.dart';
import 'geologic_timeline.dart';
import 'museum_card_frame.dart';
import 'site_card_dimensions.dart';
import 'site_card_image.dart';
import 'site_card_related_lists.dart';
import 'site_card_user_timeline.dart';

class SiteCardBack extends StatelessWidget {
  const SiteCardBack({
    super.key,
    required this.site,
    this.titleFontSize = 28,
    this.subtitleFontSize = 12,
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
    final rockPart = site.rockType ?? site.siteTypeRockType ?? '';
    final rockText = rockPart.trim().isNotEmpty
        ? toTitleCase(rockPart.trim())
        : '';
    final periodPart = site.titleIsRevealed ? site.displayPeriod : 'Age Hidden';
    final periodLine = rockText.isNotEmpty
        ? '$periodPart · $rockText'
        : periodPart;

    return MuseumCardFrame(
      image: SiteCardImage(imageUrl: site.mainImageUrl),
      title: site.displayTitle,
      subtitle: periodLine,
      titleFontSize: titleFontSize,
      subtitleFontSize: subtitleFontSize,
      fillBody: false,
      timeline: GeologicTimeline.fromAgeRange(
        minAgeMa: site.titleIsRevealed ? site.minAgeMa : null,
        maxAgeMa: site.titleIsRevealed ? site.maxAgeMa : null,
        axis: GeologicTimelineAxis.horizontal,
        scale: 0.92,
        showYearLabels: true,
      ),
      panels: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardBackSection(
            title: 'Site dimensions',
            child: SizedBox(
              height: 132,
              child: SiteCardDimensions(site: site),
            ),
          ),
          SiteCardFossils(
            siteId: site.siteId,
            thumbSize: 64,
            tappable: true,
            use2Rows: false,
            sectionTitle: 'Fossils',
            hideWhenEmpty: true,
          ),
        ],
      ),
      onHistory: () => SiteCardUserTimeline.showDrawer(context, site: site),
    );
  }
}
