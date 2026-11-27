import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/relative_time.dart';
import '../dino/dinosaur_article_drawer.dart';
import 'card_attribute_grid.dart';
import 'card_back_backdrop.dart';
import 'card_back_body.dart';
import 'card_back_corner_actions.dart';
import 'card_history_drawer.dart';
import 'cladogram_strip.dart';
import 'dinosaur_card_header.dart';
import 'dinosaur_card_image.dart';
import 'geologic_timeline.dart';

class DinosaurCardBack extends StatelessWidget {
  const DinosaurCardBack({
    super.key,
    required this.dinosaur,
    this.showArticleButton = true,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
  });

  final DinosaurSummary dinosaur;
  final bool showArticleButton;
  final double titleFontSize;
  final double subtitleFontSize;

  static List<CardAttributeItem> _attributeItems(DinosaurSummary dinosaur) => [
    CardAttributeItem(
      'Period',
      dinosaur.displayPeriodName == '—' ? '—' : dinosaur.displayPeriodName,
    ),
    CardAttributeItem('Diet', dinosaur.dietType ?? '—'),
    CardAttributeItem('Mass', dinosaur.mass ?? '—'),
    CardAttributeItem('Length', dinosaur.length ?? '—'),
  ];

  void _openHistory(BuildContext context) {
    final whenLabel = dinosaur.createdAt != null
        ? formatRelativeWhen(dinosaur.createdAt!)
        : '—';
    CardHistoryDrawer.show(
      context,
      title: 'History',
      child: Text(
        'Reconstructed · $whenLabel',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final nodes = dinosaur.cladogramNodes();

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(
            image: DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: DinosaurCardHeader(
              dinosaur: dinosaur,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
              subtitleOverride: '',
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 72,
            // Clear the bottom-right wiki/history row.
            bottom: 44,
            child: CardBackBody(
              children: [
                CardBackSection(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dinosaur.displayPeriod,
                        textAlign: TextAlign.center,
                        style: cardTheme
                            .bodyStyle(fontSize: 12.5)
                            .copyWith(
                              color: cardTheme.cardTextPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 48,
                        child: GeologicTimeline(
                          birth: dinosaur.birth,
                          death: dinosaur.death,
                          axis: GeologicTimelineAxis.horizontal,
                          scale: 1.0,
                          showYearLabels: true,
                        ),
                      ),
                    ],
                  ),
                ),
                if (nodes.isEmpty)
                  CardBackSection(
                    title: 'Attributes',
                    child: CardAttributeGrid(
                      columns: 1,
                      attributes: _attributeItems(dinosaur),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: CardBackSection(
                          title: 'Attributes',
                          child: CardAttributeGrid(
                            columns: 1,
                            attributes: _attributeItems(dinosaur),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CardBackSection(
                          title: 'Cladogram',
                          child: CladogramStrip(
                            nodes: nodes,
                            scale: 0.85,
                            centered: false,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          CardBackCornerActions(
            wiki: showArticleButton
                ? () => DinosaurArticleDrawer.show(context, dinosaur: dinosaur)
                : null,
            onHistory: () => _openHistory(context),
          ),
        ],
      ),
    );
  }
}
