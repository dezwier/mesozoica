import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Same cover illustration as the front face, slightly blurred, plus a soft
/// glare wash.
///
/// Card-back content (headers, panels) is layered by callers on top of this.
class CardBackBackdrop extends StatelessWidget {
  const CardBackBackdrop({super.key, required this.image});

  final Widget image;

  static const _blurSigma = 3.0;

  /// Oversample so the soft blur fringe is clipped away (avoids a white halo
  /// on rounded edges, especially while the card rotates).
  static const _blurOverscale = 1.1;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dark underlay: any residual edge samples dark, not white/transparent.
        const ColoredBox(color: Color(0xFF0A0A0A)),
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: _blurSigma,
              sigmaY: _blurSigma,
              tileMode: TileMode.clamp,
            ),
            child: Transform.scale(
              scale: _blurOverscale,
              filterQuality: FilterQuality.medium,
              child: image,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: cardTheme.backFaceSheenGradient(),
          ),
        ),
      ],
    );
  }
}
