import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Sharp hero across the top quarter of a card back.
///
/// The window shows the second quarter of the card-aspect image, counting
/// from the top, and never stretches it.
class CardBackBackdrop extends StatelessWidget {
  const CardBackBackdrop({super.key, required this.image});

  final Widget image;

  /// Fraction of the card height occupied by the illustration.
  static const heroFraction = 0.25;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final body = cardTheme.museumBodyColor;
    return ColoredBox(
      color: body,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _SecondQuarterHero(image: image),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x40000000),
                  const Color(0x00000000),
                  body.withValues(alpha: 0.2),
                  body,
                  body,
                ],
                stops: const [0.0, 0.12, 0.20, 0.25, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondQuarterHero extends StatelessWidget {
  const _SecondQuarterHero({required this.image});

  final Widget image;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final cardHeight = constraints.maxHeight;
        final heroHeight = cardHeight * CardBackBackdrop.heroFraction;
        return Align(
          alignment: Alignment.topCenter,
          child: ClipRect(
            child: SizedBox(
              width: cardWidth,
              height: heroHeight,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minWidth: cardWidth,
                maxWidth: cardWidth,
                minHeight: cardHeight,
                maxHeight: cardHeight,
                child: Transform.translate(
                  offset: Offset(0, -heroHeight),
                  child: SizedBox(
                    width: cardWidth,
                    height: cardHeight,
                    child: image,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
