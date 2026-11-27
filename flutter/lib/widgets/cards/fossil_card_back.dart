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
import 'museum_card_icons.dart';

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
      emblem: MuseumGlyph.bone,
      title: fossil.displayTitle,
      subtitle: subtitle,
      titleFontSize: titleFontSize,
      subtitleFontSize: subtitleFontSize,
      fillBody: false,
      timeline: GeologicTimeline.fromAgeRange(
        minAgeMa: fossil.minAgeMa,
        maxAgeMa: fossil.maxAgeMa,
        axis: GeologicTimelineAxis.horizontal,
        scale: 0.92,
        showYearLabels: true,
      ),
      panels: MuseumPanelRow(
        left: CardBackSection(
          title: 'Attributes',
          child: CardAttributeGrid(
            attributes: [
              CardAttributeItem('Category', fossil.displayImpCategory),
              CardAttributeItem('Sub category', fossil.displayImpSubcategory),
              CardAttributeItem(
                'Preservation',
                fossil.displayImpPreservationQuality,
              ),
              CardAttributeItem('Completeness', fossil.displayImpCompleteness),
            ],
          ),
        ),
        right: CardBackSection(
          title: 'Linked cards',
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 148),
              child: FossilRelatedThumbs(fossil: fossil),
            ),
          ),
        ),
      ),
      wiki: showWiki
          ? () => FossilRecordDrawer.show(context, fossil: fossil)
          : null,
      onHistory: () => _openHistory(context),
    );
  }
}
