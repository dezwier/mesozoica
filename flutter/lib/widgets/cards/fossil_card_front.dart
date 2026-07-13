import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/fossil.dart';
import '../../theme/dino_card_theme.dart';
import 'fossil_card_edge_facts.dart';
import 'fossil_card_header.dart';
import 'fossil_card_image.dart';

class FossilCardFront extends StatelessWidget {
  const FossilCardFront({
    super.key,
    required this.fossil,
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.38,
  });

  final FossilSummary fossil;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FossilCardImage(imageUrl: fossil.mainImageUrl),
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
              showOccurrenceSubtitle: true,
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: overlayHeightFactor,
                widthFactor: 1,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    10,
                    18,
                    math.max(14, titleFontSize * 0.55),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FossilCardEdgeFacts(fossil: fossil),
                    ],
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
