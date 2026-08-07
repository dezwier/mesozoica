import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
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
    return CardSectionPanel(
      padding: EdgeInsets.zero,
      clipChild: true,
      expandChild: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SiteCardImage(imageUrl: site.mainImageUrl),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isOpen
                    ? [Colors.black54, Colors.black87]
                  : [Colors.black45, Colors.black87],
              ),
            ),
          ),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: GeologicTimeline.fromAgeRange(
                        minAgeMa: site.titleIsRevealed ? site.minAgeMa : null,
                        maxAgeMa: site.titleIsRevealed ? site.maxAgeMa : null,
                        axis: GeologicTimelineAxis.horizontal,
                        scale: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    site.titleIsRevealed ? site.displayPeriod : 'Age Hidden',
                    textAlign: TextAlign.center,
                    style: cardTheme.bodyStyle(fontSize: 10).copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            Center(
              child: Text(
                'GEOLOGIC AGE',
                style: cardTheme.sectionLabelStyle(fontSize: 9).copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
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
    return CardSectionPanel(
      label: isOpen ? 'Located Fossils' : null,
      labelGap: isOpen ? 6 : 0,
      expandChild: true,
      padding: isOpen
          ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
          : const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: SiteCardFossils(
        siteId: siteId,
        thumbSize: isOpen ? 76 : 44,
      ),
    );
  }
}
