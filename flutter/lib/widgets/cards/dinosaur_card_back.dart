import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import '../../utils/relative_time.dart';
import '../dino/dinosaur_article_drawer.dart';
import 'card_accordion_layout.dart';
import 'card_attribute_grid.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
import 'card_timeline_history.dart';
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

  static const _contentScale = 1.15;

  @override
  Widget build(BuildContext context) {
    final nodes = dinosaur.cladogramNodes();
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: cardTheme.cardTextSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

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
              subtitleOverride: "", // Drop subtitle for dinosaur cards on back
            ),
          ),
          if (showArticleButton)
            Positioned(
              top: 14,
              right: 10,
              child: IconButton(
                onPressed: () =>
                    DinosaurArticleDrawer.show(context, dinosaur: dinosaur),
                icon: const Icon(Icons.info_outline, size: 18),
                color: const Color(0xE6F5F0E8),
                tooltip: 'Read article',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
          Positioned(
            left: 18,
            right: 18,
            top: 72, // Align the top offset of the accordion layout to exactly 72
            bottom: 14,
            child: CardAccordionLayout(
              initialIndex: 0,
              items: [
                // Element 0: Dinosaur period and rock type
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    return _DinosaurPeriodRockTypeBox(
                      dinosaur: dinosaur,
                      isOpen: isOpen,
                      curvedT: curvedT,
                      lerpFn: lerpFn,
                    );
                  },
                ),
                // Element 1: Dinosaur attributes (generalized CardAttributeGrid)
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    final attributesList = [
                      CardAttributeItem('Period', dinosaur.displayPeriodName == '—' ? '—' : dinosaur.displayPeriodName),
                      CardAttributeItem('Diet', dinosaur.dietType ?? '—'),
                      CardAttributeItem('Mass', dinosaur.mass ?? '—'),
                      CardAttributeItem('Length', dinosaur.length ?? '—'),
                    ];
                    return CardSectionPanel(
                      labelWidget: Text(
                        'Dinosaur attributes'.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: titleStyle,
                      ),
                      labelGap: 6,
                      expandChild: true,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: isOpen
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: SizedBox(
                                height: 112,
                                child: CardAttributeGrid(
                                  attributes: attributesList,
                                  isOpen: isOpen,
                                ),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: SizedBox(
                                height: 22,
                                child: CardAttributeGrid(
                                  attributes: attributesList,
                                  isOpen: isOpen,
                                ),
                              ),
                            ),
                    );
                  },
                ),
                // Element 2: Dinosaur cladogram
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    return CardSectionPanel(
                      labelWidget: Text(
                        'Dinosaur cladogram'.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: titleStyle,
                      ),
                      labelGap: 6,
                      expandChild: true,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: isOpen
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: SizedBox(
                                height: 112,
                                child: CladogramStrip(
                                  nodes: nodes,
                                  scale: _contentScale,
                                  centered: true,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
                // Element 3: Dinosaur timeline history
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    final timelineHeight = lerpFn(22.0, 44.0);
                    return DinosaurCardUserTimeline(
                      dinosaur: dinosaur,
                      isOpen: isOpen,
                      height: timelineHeight,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DinosaurPeriodRockTypeBox extends StatelessWidget {
  const _DinosaurPeriodRockTypeBox({
    required this.dinosaur,
    required this.isOpen,
    required this.curvedT,
    required this.lerpFn,
  });

  final DinosaurSummary dinosaur;
  final bool isOpen;
  final double curvedT;
  final double Function(double start, double end) lerpFn;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: Colors.white.withValues(alpha: 0.9),
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    final String explanation = dinosaur.displayPeriod;
    final double subboxHeight = lerpFn(18.0, 112.0);

    return CardSectionPanel(
      padding: EdgeInsets.zero,
      clipChild: true,
      expandChild: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ClipRect(
              child: OverflowBox(
                minHeight: 220,
                maxHeight: 220,
                child: DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.black87],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dinosaur period and rock type'.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: titleStyle,
                ),
                if (isOpen) ...[
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      height: subboxHeight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: CardSectionPanel(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              clipChild: true,
                              child: SizedBox(
                                height: 52,
                                width: 310,
                                child: GeologicTimeline(
                                  birth: dinosaur.birth,
                                  death: dinosaur.death,
                                  axis: GeologicTimelineAxis.horizontal,
                                  scale: 1.0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            explanation,
                            textAlign: TextAlign.center,
                            style: cardTheme.bodyStyle(fontSize: 12).copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Center(
                    child: SizedBox(
                      height: 16,
                      width: 280,
                      child: GeologicTimeline(
                        birth: dinosaur.birth,
                        death: dinosaur.death,
                        axis: GeologicTimelineAxis.horizontal,
                        scale: 0.65,
                        showYearLabels: false,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DinosaurCardUserTimeline extends StatelessWidget {
  const DinosaurCardUserTimeline({
    super.key,
    required this.dinosaur,
    this.isOpen = true,
    this.height,
  });

  final DinosaurSummary dinosaur;
  final bool isOpen;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: cardTheme.cardTextSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    final resolvedHeight = height ?? (isOpen ? 44.0 : 22.0);
    final at = dinosaur.createdAt;

    final events = [
      if (at != null)
        CardTimelineEvent(
          status: 'Reconstructed',
          when: formatRelativeWhen(at),
          detail: 'Collection',
          isHighlight: true,
        ),
    ];

    return CardSectionPanel(
      labelWidget: Text(
        'Dinosaur timeline history'.toUpperCase(),
        textAlign: TextAlign.center,
        style: titleStyle,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      labelGap: 6,
      expandChild: true,
      child: SizedBox(
        height: resolvedHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: CardTimelineHistory(
            events: events,
            isOpen: isOpen,
          ),
        ),
      ),
    );
  }
}
