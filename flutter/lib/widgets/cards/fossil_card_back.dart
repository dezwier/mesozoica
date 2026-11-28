import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../utils/display_text.dart';
import '../../utils/relative_time.dart';
import '../fossil/fossil_record_drawer.dart';
import 'card_attribute_grid.dart';
import 'card_back_body.dart';
import 'card_history_drawer.dart';
import 'fossil_card_image.dart';
import 'fossil_related_thumbs.dart';
import 'geologic_timeline.dart';
import 'museum_card_frame.dart';

class FossilCardBack extends StatelessWidget {
  const FossilCardBack({
    super.key,
    required this.fossil,
    this.showRecordButton = true,
    this.titleFontSize = 28,
    this.subtitleFontSize = 12,
  });

  final FossilSummary fossil;
  final bool showRecordButton;
  final double titleFontSize;
  final double subtitleFontSize;

  void _openHistory(BuildContext context) {
    final whenLabel = fossil.discoveredAt != null
        ? formatRelativeWhen(fossil.discoveredAt!)
        : '—';
    CardHistoryDrawer.show(
      context,
      title: 'History',
      child: Text(
        'Discovered · $whenLabel',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discoveredSubtitle = fossil.discoveredSubtitle;
    final rockPart = fossil.displayRockType;
    final rockText = rockPart != '—' ? toTitleCase(rockPart.trim()) : '';
    final periodPart = fossil.displayPeriod;
    final periodLine = rockText.isNotEmpty
        ? '$periodPart · $rockText'
        : periodPart;
    final subtitle =
        (discoveredSubtitle != null && discoveredSubtitle.isNotEmpty)
        ? discoveredSubtitle
        : (periodLine == '—' ? null : periodLine);
    final showWiki = showRecordButton && !fossil.isField;

    return MuseumCardFrame(
      image: FossilCardImage(imageUrl: fossil.mainImageUrl),
      title: fossil.displayTitle,
      subtitle: subtitle,
      titleFontSize: titleFontSize,
      subtitleFontSize: subtitleFontSize,
      timeline: GeologicTimeline.fromAgeRange(
        minAgeMa: fossil.minAgeMa,
        maxAgeMa: fossil.maxAgeMa,
        axis: GeologicTimelineAxis.horizontal,
        scale: 0.92,
        showYearLabels: true,
      ),
      fillBody: true,
      panels: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CardBackSection(
              expandChild: true,
              title: 'Attributes',
              child: CardAttributeGrid(
                columns: 2,
                fill: true,
                attributes: [
                  CardAttributeItem('Category', fossil.displayImpCategory),
                  CardAttributeItem(
                    'Sub category',
                    fossil.displayImpSubcategory,
                  ),
                  CardAttributeItem(
                    'Preservation',
                    fossil.displayImpPreservationQuality,
                  ),
                  CardAttributeItem(
                    'Completeness',
                    fossil.displayImpCompleteness,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          CardBackSection(
            title: 'Linked cards',
            child: SizedBox(
              height: 88,
              child: FossilRelatedThumbs(fossil: fossil),
            ),
          ),
        ],
      ),
      wiki: showWiki
          ? () => FossilRecordDrawer.show(context, fossil: fossil)
          : null,
      onHistory: () => _openHistory(context),
    );
  }
}
