import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'card_accordion_layout.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
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
            child: CardAccordionLayout(
              initialIndex: 0,
              items: [
                // Element 0: Period / Rock Type
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    return _PeriodRockTypeBox(
                      site: site,
                      isOpen: isOpen,
                      curvedT: curvedT,
                      lerpFn: lerpFn,
                    );
                  },
                ),
                // Element 1: Site dimensions
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    return SiteCardDimensions(
                      site: site,
                      isOpen: isOpen,
                    );
                  },
                ),
                // Element 2: Fossils
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    final thumbSize = lerpFn(44.0, 76.0);
                    return _FossilsBox(
                      siteId: site.siteId,
                      isOpen: isOpen,
                      thumbSize: thumbSize,
                    );
                  },
                ),
                // Element 3: History timeline
                CardAccordionItem(
                  builder: (context, isOpen, curvedT, lerpFn) {
                    final timelineHeight = lerpFn(22.0, 44.0);
                    return SiteCardUserTimeline(
                      site: site,
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

class _PeriodRockTypeBox extends StatelessWidget {
  const _PeriodRockTypeBox({
    required this.site,
    required this.isOpen,
    required this.curvedT,
    required this.lerpFn,
  });

  final SiteSummary site;
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

    final String rockPart = site.rockType ?? site.siteTypeRockType ?? '';
    final String rockText = rockPart.trim().isNotEmpty ? toTitleCase(rockPart.trim()) : '';
    final String periodPart = site.titleIsRevealed ? site.displayPeriod : 'Age Hidden';
    final String explanation = rockText.isNotEmpty ? '$periodPart · $rockText' : periodPart;

    return CardSectionPanel(
      labelWidget: Text(
        'Site period and rock type'.toUpperCase(),
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
                    minAgeMa: site.titleIsRevealed ? site.minAgeMa : null,
                    maxAgeMa: site.titleIsRevealed ? site.maxAgeMa : null,
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

class _FossilsBox extends StatelessWidget {
  const _FossilsBox({
    required this.siteId,
    required this.isOpen,
    required this.thumbSize,
  });

  final int siteId;
  final bool isOpen;
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: cardTheme.cardTextSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    final resolvedHeight = isOpen ? 126.0 : 22.0;

    return CardSectionPanel(
      labelWidget: Text(
        'Site fossils'.toUpperCase(),
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
          height: resolvedHeight,
          width: 340,
          child: SiteCardFossils(
            siteId: siteId,
            thumbSize: thumbSize,
            tappable: isOpen,
            isOpen: isOpen,
            use2Rows: true,
          ),
        ),
      ),
    );
  }
}
