import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'card_corner_inset.dart';
import 'dinosaur_card_dialog.dart';
import 'dinosaur_card_image.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';
import 'site_card_dialog.dart';
import 'site_card_image.dart';

class FossilCardFront extends StatelessWidget {
  const FossilCardFront({
    super.key,
    required this.fossil,
    this.titleFontSize = 28,
    this.overlayHeightFactor = 0.35,
    this.insetSizeFactor = 0.28,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final double overlayHeightFactor;
  final double insetSizeFactor;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final insetSize = math
        .max(72.0, MediaQuery.sizeOf(context).width * insetSizeFactor)
        .toDouble();

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FossilCardImage(imageUrl: fossil.mainImageUrl),
          if (fossil.siteId != null)
            Positioned(
              top: 12,
              left: 12,
              child: CardCornerInset(
                size: insetSize,
                onTap: () => showSiteCardDialog(
                  context,
                  siteId: fossil.siteId!,
                ),
                child: SiteCardImage(imageUrl: fossil.siteMainImageUrl),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: CardCornerInset(
              size: insetSize,
              onTap: () => showDinosaurCardDialog(
                context,
                dinosaurId: fossil.dinosaurId,
              ),
              child: DinosaurCardImage(imageUrl: fossil.dinosaurMainImageUrl),
            ),
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
                          FossilCardHeader(
                            fossil: fossil,
                            titleFontSize: titleFontSize,
                            centered: true,
                            useFrontTitleStyle: true,
                            showOccurrenceSubtitle: true,
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
