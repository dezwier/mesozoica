import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../dino/dinosaur_article_drawer.dart';
import 'dinosaur_card_header.dart';
import 'dinosaur_card_image.dart';
import 'dinosaur_card_edge_facts.dart';

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
              left: 0,
              top: 44,
              bottom: 0,
              width: 88,
              child: Column(
                children: [
                  Expanded(
                    flex: ((1 - overlayHeightFactor) * 100).round().clamp(1, 100),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DinosaurCardEdgeFacts(dinosaur: dinosaur),
                    ),
                  ),
                  Expanded(
                    flex: (overlayHeightFactor * 100).round().clamp(1, 100),
                    child: const SizedBox.shrink(),
                  ),
                ],
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
