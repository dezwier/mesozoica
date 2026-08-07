import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';
import 'card_back_backdrop.dart';
import 'card_section_panel.dart';
import 'card_world_map.dart';
import 'geologic_timeline.dart';
import 'site_card_dimensions.dart';
import 'site_card_header.dart';
import 'site_card_image.dart';
import 'site_card_related_lists.dart';
import 'site_card_user_timeline.dart';

class SiteCardBack extends StatefulWidget {
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
  State<SiteCardBack> createState() => _SiteCardBackState();
}

class _SiteCardBackState extends State<SiteCardBack> with TickerProviderStateMixin {
  int _expandedIndex = 0;
  int _previousIndex = 0;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapIndex(int index) {
    if (index == _expandedIndex) return;
    setState(() {
      _previousIndex = _expandedIndex;
      _expandedIndex = index;
      _controller.forward(from: 0.0);
    });
  }

  double _getWeight(int index, double t) {
    const closedW = 1.0;
    const openW = 3.5;

    if (index == _expandedIndex) {
      return closedW + (openW - closedW) * t;
    } else if (index == _previousIndex) {
      return openW + (closedW - openW) * t;
    } else {
      return closedW;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardBackBackdrop(image: SiteCardImage(imageUrl: widget.site.mainImageUrl)),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: SiteCardHeader(
              site: widget.site,
              titleFontSize: widget.titleFontSize,
              subtitleFontSize: widget.subtitleFontSize,
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
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double curvedT = const Cubic(0.2, 0.0, 0.2, 1.0).transform(_controller.value);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Element 0: Period / Rock Type
                    Expanded(
                      flex: (_getWeight(0, curvedT) * 1000).round(),
                      child: GestureDetector(
                        onTap: _expandedIndex == 0 ? null : () => _onTapIndex(0),
                        behavior: HitTestBehavior.opaque,
                        child: _PeriodRockTypeBox(
                          site: widget.site,
                          isOpen: _expandedIndex == 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Element 1: Site dimensions
                    Expanded(
                      flex: (_getWeight(1, curvedT) * 1000).round(),
                      child: GestureDetector(
                        onTap: _expandedIndex == 1 ? null : () => _onTapIndex(1),
                        behavior: HitTestBehavior.opaque,
                        child: SiteCardDimensions(
                          site: widget.site,
                          isOpen: _expandedIndex == 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Element 2: Fossils
                    Expanded(
                      flex: (_getWeight(2, curvedT) * 1000).round(),
                      child: GestureDetector(
                        onTap: _expandedIndex == 2 ? null : () => _onTapIndex(2),
                        behavior: HitTestBehavior.opaque,
                        child: _FossilsBox(
                          siteId: widget.site.siteId,
                          isOpen: _expandedIndex == 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Element 3: History timeline
                    Expanded(
                      flex: (_getWeight(3, curvedT) * 1000).round(),
                      child: GestureDetector(
                        onTap: _expandedIndex == 3 ? null : () => _onTapIndex(3),
                        behavior: HitTestBehavior.opaque,
                        child: SiteCardUserTimeline(
                          site: widget.site,
                          isOpen: _expandedIndex == 3,
                        ),
                      ),
                    ),
                  ],
                );
              },
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
  });

  final SiteSummary site;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: Colors.white.withValues(alpha: 0.9),
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    final String rockPart = site.rockType ?? site.siteTypeRockType ?? '';
    final String rockText = rockPart.trim().isNotEmpty ? toTitleCase(rockPart.trim()) : '';
    final String periodPart = site.titleIsRevealed ? site.displayPeriod : 'Age Hidden';
    final String explanation = rockText.isNotEmpty ? '$periodPart · $rockText' : periodPart;

    return CardSectionPanel(
      padding: EdgeInsets.zero,
      clipChild: true,
      expandChild: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image centered, never stretched or squished vertically
          Positioned.fill(
            child: ClipRect(
              child: OverflowBox(
                minHeight: 220,
                maxHeight: 220,
                child: SiteCardImage(imageUrl: site.mainImageUrl),
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
                  'Site period and rock type'.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: titleStyle,
                ),
                if (isOpen) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: CardSectionPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      clipChild: true,
                      child: SizedBox(
                        height: 52,
                        width: 310,
                        child: GeologicTimeline.fromAgeRange(
                          minAgeMa: site.titleIsRevealed ? site.minAgeMa : null,
                          maxAgeMa: site.titleIsRevealed ? site.maxAgeMa : null,
                          axis: GeologicTimelineAxis.horizontal,
                          scale: 0.85,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    explanation,
                    textAlign: TextAlign.center,
                    style: cardTheme.bodyStyle(fontSize: 10).copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
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

class _FossilsBox extends StatelessWidget {
  const _FossilsBox({
    required this.siteId,
    required this.isOpen,
  });

  final int siteId;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final titleStyle = cardTheme.sectionLabelStyle(fontSize: 8.5).copyWith(
          color: cardTheme.cardTextSecondary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.bold,
        );

    return CardSectionPanel(
      labelWidget: Text(
        'Site fossils'.toUpperCase(),
        textAlign: TextAlign.center,
        style: titleStyle,
      ),
      labelGap: 6,
      expandChild: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SiteCardFossils(
        siteId: siteId,
        thumbSize: isOpen ? 76 : 44,
        tappable: isOpen,
      ),
    );
  }
}
