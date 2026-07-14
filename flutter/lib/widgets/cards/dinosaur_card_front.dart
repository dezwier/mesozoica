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
    this.titleFontSize = 36,
    this.subtitleFontSize = 10,
    this.overlayHeightFactor = 0.52,
    this.factsFadeAnimation,
  });

  final DinosaurSummary dinosaur;
  final bool showFacts;
  final double titleFontSize;
  final double subtitleFontSize;
  final double overlayHeightFactor;
  final Animation<double>? factsFadeAnimation;

  String get _description =>
      dinosaur.shortDescription != null &&
              dinosaur.shortDescription!.trim().isNotEmpty
          ? dinosaur.shortDescription!.trim()
          : '—';

  Widget _buildFactsSection(DinoCardTheme cardTheme) {
    final facts = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _description,
          textAlign: TextAlign.center,
          style: cardTheme.frontOverlayBodyStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        DinosaurCardEdgeFacts(dinosaur: dinosaur),
      ],
    );

    final animation = factsFadeAnimation;
    if (animation != null) {
      return FadeTransition(
        opacity: animation,
        child: IgnorePointer(
          ignoring: animation.value < 0.05,
          child: facts,
        ),
      );
    }

    if (!showFacts) return const SizedBox.shrink();
    return facts;
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final factsVisible = factsFadeAnimation != null
        ? factsFadeAnimation!.value > 0.001
        : showFacts;

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DinosaurCardImage(imageUrl: dinosaur.mainImageUrl),
          Positioned(
            left: 18,
            right: 18,
            top: 20,
            child: DinosaurCardHeader(
              dinosaur: dinosaur,
              titleFontSize: titleFontSize,
              subtitleFontSize: subtitleFontSize,
              centered: true,
              overlayOnImage: true,
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
                    factsVisible ? 16 : math.max(8, titleFontSize * 0.45),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildFactsSection(cardTheme),
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
