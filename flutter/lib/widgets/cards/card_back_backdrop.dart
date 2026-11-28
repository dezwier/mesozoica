import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Sharp hero across the top of a card back.
///
/// The window shows the second quarter of the card-aspect image, counting
/// from the top, and never stretches it.
class CardBackBackdrop extends StatelessWidget {
  const CardBackBackdrop({
    super.key,
    required this.image,
    this.heroFraction = defaultHeroFraction,
  });

  final Widget image;

  /// Fraction of the card height occupied by the illustration.
  final double heroFraction;

  static const defaultHeroFraction = 0.25;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final body = cardTheme.museumBodyColor;
    final hero = heroFraction.clamp(0.08, 0.4);
    return ColoredBox(
      color: body,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _SecondQuarterHero(image: image, heroFraction: hero),
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
                stops: [
                  0.0,
                  hero * 0.48,
                  hero * 0.80,
                  hero,
                  1.0,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondQuarterHero extends StatelessWidget {
  const _SecondQuarterHero({required this.image, required this.heroFraction});

  final Widget image;
  final double heroFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final cardHeight = constraints.maxHeight;
        final heroHeight = cardHeight * heroFraction;
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
