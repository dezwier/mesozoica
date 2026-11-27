import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import '../../utils/relative_time.dart';
import '../fossil/fossil_record_drawer.dart';
import 'card_attribute_grid.dart';
import 'card_back_backdrop.dart';
import 'card_back_body.dart';
import 'card_back_corner_actions.dart';
import 'card_history_drawer.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';
import 'fossil_related_thumbs.dart';
import 'geologic_timeline.dart';

class FossilCardBack extends StatelessWidget {
  const FossilCardBack({
    super.key,
    required this.fossil,
    this.showRecordButton = true,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
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
    final cardTheme = DinoCardTheme.of(context);
    final discoveredSubtitle = fossil.discoveredSubtitle;
    final rockPart = fossil.displayRockType;
    final rockText = rockPart != '—' ? toTitleCase(rockPart.trim()) : '';
    final periodPart = fossil.displayPeriod;
    final periodLine =
        rockText.isNotEmpty ? '$periodPart · $rockText' : periodPart;
    final showWiki = showRecordButton && !fossil.isField;

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(
            image: FossilCardImage(imageUrl: fossil.mainImageUrl),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: FossilCardHeader(
              fossil: fossil,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
              showOccurrenceSubtitle: false,
              subtitleOverride: discoveredSubtitle,
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
                          minAgeMa: fossil.minAgeMa,
                          maxAgeMa: fossil.maxAgeMa,
                          axis: GeologicTimelineAxis.horizontal,
                          scale: 1.0,
                          showYearLabels: true,
                        ),
                      ),
                    ],
                  ),
                ),
                CardBackSection(
                  title: 'Attributes',
                  child: CardAttributeGrid(
                    attributes: [
                      CardAttributeItem(
                        'Category',
                        fossil.displayImpCategory,
                      ),
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
                CardBackSection(
                  title: 'Linked cards',
                  child: SizedBox(
                    height: 96,
                    child: FossilRelatedThumbs(fossil: fossil),
                  ),
                ),
              ],
            ),
          ),
          CardBackCornerActions(
            wiki: showWiki
                ? () => FossilRecordDrawer.show(context, fossil: fossil)
                : null,
            onHistory: () => _openHistory(context),
          ),
        ],
      ),
    );
  }
}
