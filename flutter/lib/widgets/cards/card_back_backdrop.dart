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
    this.fullCardSize,
  });

  final Widget image;

  /// Fraction of the card height occupied by the illustration.
  /// Ignored when [fullCardSize] is set and this widget is sized to the hero.
  final double heroFraction;

  /// When set (bottom-stack mode), crop against the full card size while this
  /// widget fills its parent (the flexible hero slot).
  final Size? fullCardSize;

  static const defaultHeroFraction = 0.25;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final body = cardTheme.museumBodyColor;
    return ColoredBox(
      color: body,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = fullCardSize?.width ?? constraints.maxWidth;
          final cardHeight = fullCardSize?.height ?? constraints.maxHeight;
          final heroHeight = fullCardSize != null
              ? constraints.maxHeight
              : cardHeight * heroFraction.clamp(0.08, 0.45);
          if (heroHeight <= 0 || cardHeight <= 0) {
            return const SizedBox.shrink();
          }
          final heroStop = fullCardSize != null
              ? 1.0
              : (heroHeight / cardHeight).clamp(0.08, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ClipRect(
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: fullCardSize != null
                        ? constraints.maxHeight
                        : heroHeight,
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
              ),
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
                    stops: fullCardSize != null
                        ? const [0.0, 0.35, 0.72, 0.92, 1.0]
                        : [
                            0.0,
                            heroStop * 0.48,
                            heroStop * 0.80,
                            heroStop,
                            1.0,
                          ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
