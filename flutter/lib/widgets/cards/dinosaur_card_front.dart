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
                heightFactor: 0.62,
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        DinoCardTheme.cardBackground.withValues(alpha: 0.85),
                        DinoCardTheme.cardBackground,
                      ],
                      stops: const [0.0, 0.35, 1.0],
                    ),
                  ),
                  child: ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DinosaurCardHeader(
                            dinosaur: dinosaur,
                            titleFontSize: 15,
                            subtitleFontSize: 9,
                          ),
                          const SizedBox(height: 6),
                          DinosaurCardFacts(
                            dinosaur: dinosaur,
                            compact: true,
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
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                icon: const Icon(Icons.info_outline, size: 18),
                color: DinoCardTheme.cardAccent,
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
