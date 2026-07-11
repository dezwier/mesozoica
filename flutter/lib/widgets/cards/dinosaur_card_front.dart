import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../dino/dinosaur_article_drawer.dart';

class DinosaurCardFront extends StatelessWidget {
  const DinosaurCardFront({super.key, required this.dinosaur});

  final DinosaurSummary dinosaur;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            DinoCardTheme.frontPlaceholderAsset,
            fit: BoxFit.cover,
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
