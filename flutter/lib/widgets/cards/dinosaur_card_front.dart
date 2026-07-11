import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../dino/dinosaur_article_drawer.dart';
import 'dinosaur_card_facts.dart';
import 'dinosaur_card_header.dart';

class DinosaurCardFront extends StatelessWidget {
  const DinosaurCardFront({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return AspectRatio(
      aspectRatio: DinoCardTheme.cardAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            DinoCardTheme.frontPlaceholderAsset,
            fit: BoxFit.cover,
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.45,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: cardTheme.frontOverlayGradient(),
                  ),
                  child: ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          DinosaurCardHeader(
                            dinosaur: dinosaur,
                            titleFontSize: 17,
                            subtitleFontSize: 10,
                            centered: true,
                          ),
                          const SizedBox(height: 8),
                          DinosaurCardFacts(
                            dinosaur: dinosaur,
                            compact: true,
                            centered: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: cardTheme.iconButtonBackground,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                icon: const Icon(Icons.info_outline, size: 18),
                color: cardTheme.cardAccent,
                tooltip: 'Read article',
                visualDensity: VisualDensity.compact,
                onPressed: () => DinosaurArticleDrawer.show(
                  context,
                  dinosaur: dinosaur,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
