import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Sharp cover hero across the top of a card back, fading into the museum body.
///
/// Card-back content is layered by [MuseumCardFrame] on top of this.
class CardBackBackdrop extends StatelessWidget {
  const CardBackBackdrop({super.key, required this.image});

  final Widget image;

  /// Fraction of the card height occupied by the illustration.
  static const heroFraction = 0.46;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final body = cardTheme.museumBodyColor;
    return ColoredBox(
      color: body,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: heroFraction,
              widthFactor: 1,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(width: 1086, height: 1448, child: image),
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
                  const Color(0x59000000),
                  const Color(0x00000000),
                  const Color(0x00000000),
                  body.withValues(alpha: 0.35),
                  body,
                  body,
                ],
                stops: const [0.0, 0.05, 0.26, 0.36, 0.46, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
