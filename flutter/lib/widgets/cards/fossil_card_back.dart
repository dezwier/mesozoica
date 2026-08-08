import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import '../../utils/relative_time.dart';
import '../fossil/fossil_record_drawer.dart';
import 'card_accordion_layout.dart';
import 'card_attribute_grid.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
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

  @override
  Widget build(BuildContext context) {
    final discoveredSubtitle = fossil.discoveredSubtitle;
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
          if (showRecordButton && !fossil.isField)
            Positioned(
              top: 14,
              right: 10,
              child: IconButton(
                onPressed: () =>
                    FossilRecordDrawer.show(context, fossil: fossil),
                icon: const Icon(Icons.info_outline, size: 18),
                color: const Color(0xE6F5F0E8),
                tooltip: 'Record details',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
          Positioned(
            left: 18,
            right: 18,
            top: 72,
            bottom: 14,
            child: CardAccordionLayout(
              initialIndex: 0,
              items: [
                // Element 0: Fossil period and rock type
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    return _FossilPeriodRockTypeBox(
                      fossil: fossil,
                      isOpen: isOpen,
                      curvedT: curvedT,
                      lerpFn: lerpFn,
                    );
                  },
                ),
                // Element 1: Fossil attributes (generalized CardAttributeGrid)
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    final attributesList = [
                      CardAttributeItem('Category', fossil.displayImpCategory),
                      CardAttributeItem('Sub category', fossil.displayImpSubcategory),
                      CardAttributeItem('Preservation quality', fossil.displayImpPreservationQuality),
                      CardAttributeItem('Completeness', fossil.displayImpCompleteness),
                    ];
                    return CardSectionPanel(
                      labelWidget: Text(
                        'Fossil attributes'.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: titleStyle,
                      ),
                      labelGap: 6,
                      expandChild: true,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: SizedBox(
                          height: isOpen ? 112.0 : 44.0,
                          width: 340,
                          child: Center(
                            child: CardAttributeGrid(
                              attributes: attributesList,
                              isOpen: isOpen,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Element 2: Fossil linked cards
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    return CardSectionPanel(
                      labelWidget: Text(
                        'Fossil linked cards'.toUpperCase(),
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
                                width: 340,
                                child: FossilRelatedThumbs(fossil: fossil),
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
                // Element 3: Fossil timeline history
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    final timelineHeight = lerpFn(22.0, 44.0);
                    return FossilCardUserTimeline(
                      fossil: fossil,
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

class _FossilPeriodRockTypeBox extends StatelessWidget {
  const _FossilPeriodRockTypeBox({
    required this.fossil,
    required this.isOpen,
    required this.curvedT,
    required this.lerpFn,
  });

  final FossilSummary fossil;
  final bool isOpen;
  final double curvedT;
  final double Function(double start, double end) lerpFn;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: cardTheme.cardTextSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    final String rockPart = fossil.displayRockType;
    final String rockText = rockPart != '—' ? toTitleCase(rockPart.trim()) : '';
    final String periodPart = fossil.displayPeriod;
    final String explanation = rockText.isNotEmpty ? '$periodPart · $rockText' : periodPart;

    return CardSectionPanel(
      labelWidget: Text(
        'Fossil period and rock type'.toUpperCase(),
        textAlign: TextAlign.center,
        style: titleStyle,
      ),
      labelGap: 6,
      expandChild: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: FittedBox(
        key: ValueKey(isOpen),
        fit: BoxFit.scaleDown,
        alignment: isOpen ? Alignment.topCenter : Alignment.center,
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisAlignment: isOpen ? MainAxisAlignment.start : MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Center(
                child: SizedBox(
                  height: 52,
                  child: GeologicTimeline.fromAgeRange(
                    minAgeMa: fossil.minAgeMa,
                    maxAgeMa: fossil.maxAgeMa,
                    axis: GeologicTimelineAxis.horizontal,
                    scale: 1.1,
                    showYearLabels: isOpen,
                  ),
                ),
              ),
              if (isOpen) ...[
                const SizedBox(height: 8),
                Text(
                  explanation,
                  textAlign: TextAlign.center,
                  style: cardTheme.bodyStyle(fontSize: 13.5).copyWith(
                        color: cardTheme.cardTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FossilCardUserTimeline extends StatelessWidget {
  const FossilCardUserTimeline({
    super.key,
    required this.fossil,
    this.isOpen = true,
    this.height,
  });

  final FossilSummary fossil;
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
    final at = fossil.discoveredAt;
    final whenLabel = at != null ? formatRelativeWhen(at) : '—';

    return CardSectionPanel(
      labelWidget: Text(
        'Fossil timeline history'.toUpperCase(),
        textAlign: TextAlign.center,
        style: titleStyle,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      labelGap: 6,
      expandChild: true,
      child: SizedBox(
        height: resolvedHeight,
        width: 340,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Discovered · $whenLabel',
            style: cardTheme.bodyStyle(fontSize: isOpen ? 12.0 : 12.5).copyWith(
                  fontWeight: isOpen ? FontWeight.normal : FontWeight.w600,
                  color: isOpen ? null : cardTheme.cardTextSecondary,
                ),
          ),
        ),
      ),
    );
  }
}
