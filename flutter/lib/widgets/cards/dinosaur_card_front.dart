import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../dino/dinosaur_article_drawer.dart';
import 'dinosaur_card_facts.dart';
import 'dinosaur_card_header.dart';
import 'dinosaur_card_image.dart';

class DinosaurCardFront extends StatelessWidget {
  const DinosaurCardFront({
    super.key,
    required this.dinosaur,
    this.showFacts = true,
    this.showArticleButton,
    this.titleFontSize = 28,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.45,
  });

  final DinosaurSummary dinosaur;
  final bool showFacts;
  final bool? showArticleButton;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;

  bool get _showArticleButton => showArticleButton ?? showFacts;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
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
                            DinosaurCardFacts(
                              dinosaur: dinosaur,
                              compact: true,
                              centered: true,
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
          if (_showArticleButton)
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.info_outline, size: 18),
                color: Colors.white,
                tooltip: 'Read article',
                visualDensity: VisualDensity.compact,
                onPressed: () => DinosaurArticleDrawer.show(
                  context,
                  dinosaur: dinosaur,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
