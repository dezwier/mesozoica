import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../theme/dino_card_theme.dart';
import 'site_card_edge_facts.dart';
import 'site_card_header.dart';
import 'site_card_image.dart';

class SiteCardFront extends StatelessWidget {
  const SiteCardFront({
    super.key,
    required this.site,
    this.titleFontSize = 28,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.35,
  });

  final SiteSummary site;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SiteCardImage(imageUrl: site.mainImageUrl),
          Positioned(
            right: 0,
            top: 24,
            width: 144,
            child: SiteCardEdgeFacts(site: site),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: overlayHeightFactor,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: cardTheme.frontOverlayGradient(),
                  ),
                  child: ClipRect(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        0,
                        18,
                        math.max(14, titleFontSize * 0.55),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SiteCardHeader(
                            site: site,
                            titleFontSize: titleFontSize,
                            subtitleFontSize: subtitleFontSize,
                            centered: true,
                            useFrontTitleStyle: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
