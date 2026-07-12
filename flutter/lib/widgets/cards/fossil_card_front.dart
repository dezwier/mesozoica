import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_image.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';

class FossilCardFront extends StatelessWidget {
  const FossilCardFront({
    super.key,
    required this.fossil,
    this.titleFontSize = 28,
    this.overlayHeightFactor = 0.35,
    this.dinosaurInsetWidthFactor = 0.28,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final double overlayHeightFactor;
  final double dinosaurInsetWidthFactor;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FossilCardImage(imageUrl: fossil.mainImageUrl),
          Positioned(
            top: 12,
            right: 12,
            width: math.max(72, MediaQuery.sizeOf(context).width * dinosaurInsetWidthFactor),
            child: AspectRatio(
              aspectRatio: DinoCardTheme.cardAspectRatio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cardTheme.shadowColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.5),
                  child: DinosaurCardImage(
                    imageUrl: fossil.dinosaurMainImageUrl,
                  ),
                ),
              ),
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
                        math.max(8, titleFontSize * 0.45),
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
