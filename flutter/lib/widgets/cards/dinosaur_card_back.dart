import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../utils/relative_time.dart';
import '../dino/dinosaur_article_drawer.dart';
import 'card_attribute_grid.dart';
import 'card_back_body.dart';
import 'card_history_drawer.dart';
import 'cladogram_strip.dart';
import 'dinosaur_card_image.dart';
import 'geologic_timeline.dart';
import 'museum_card_frame.dart';
import 'museum_card_icons.dart';

class DinosaurCardBack extends StatelessWidget {
  const DinosaurCardBack({
    super.key,
    required this.dinosaur,
    this.showArticleButton = true,
    this.titleFontSize = 28,
    this.subtitleFontSize = 12,
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
    final nodes = dinosaur.cladogramNodes();
    final period = dinosaur.displayPeriod;
    final attributes = CardBackSection(
      title: 'Attributes',
      expandChild: true,
      child: CardAttributeGrid(
        attributes: _attributeItems(dinosaur),
        fill: true,
      ),
    );

    return MuseumCardFrame(
      image: DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
      emblem: MuseumGlyph.skull,
      title: dinosaur.name,
      subtitle: period == '—' ? null : period,
      titleFontSize: titleFontSize,
      subtitleFontSize: subtitleFontSize,
      timeline: GeologicTimeline(
        birth: dinosaur.birth,
        death: dinosaur.death,
        axis: GeologicTimelineAxis.horizontal,
        scale: 0.92,
        showYearLabels: true,
      ),
      panels: nodes.isEmpty
          ? attributes
          : MuseumPanelRow(
              matchHeight: true,
              left: attributes,
              right: CardBackSection(
                title: 'Cladogram',
                expandChild: true,
                child: CladogramStrip(nodes: nodes, centered: false),
              ),
            ),
      wiki: showArticleButton
          ? () => DinosaurArticleDrawer.show(context, dinosaur: dinosaur)
          : null,
      onHistory: () => _openHistory(context),
    );
  }
}
