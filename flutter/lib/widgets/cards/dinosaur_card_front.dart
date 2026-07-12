import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import 'dinosaur_card_header.dart';
import 'dinosaur_card_image.dart';
import 'dinosaur_card_edge_facts.dart';

class DinosaurCardFront extends StatelessWidget {
  const DinosaurCardFront({
    super.key,
    required this.dinosaur,
    this.showFacts = true,
    this.titleFontSize = 28,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.45,
  });

  final DinosaurSummary dinosaur;
  final bool showFacts;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  String get _description =>
      dinosaur.shortDescription != null &&
              dinosaur.shortDescription!.trim().isNotEmpty
          ? dinosaur.shortDescription!.trim()
          : '—';

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
          if (showFacts)
            Positioned(
              right: 0,
              top: 24,
              width: 144,
              child: DinosaurCardEdgeFacts(dinosaur: dinosaur),
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
                        showFacts ? 16 : math.max(8, titleFontSize * 0.45),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          DinosaurCardHeader(
                            dinosaur: dinosaur,
                            titleFontSize: titleFontSize,
                            subtitleFontSize: subtitleFontSize,
                            centered: true,
                            useFrontTitleStyle: true,
                          ),
                          if (showFacts) ...[
                            const SizedBox(height: 14),
                            Text(
                              _description,
                              textAlign: TextAlign.center,
                              style: cardTheme.bodyStyle(fontSize: 12),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
