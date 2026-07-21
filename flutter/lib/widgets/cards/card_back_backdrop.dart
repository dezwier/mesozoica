import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Blurred card illustration + subtle wash and brushed-metal grain.
class CardBackBackdrop extends StatelessWidget {
  const CardBackBackdrop({
    super.key,
    required this.image,
  });

  final Widget image;

  /// Heavy blur so the illustration reads as atmosphere, not detail.
  static const double blurSigma = 32;

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Slight scale avoids transparent edges after blur.
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
              tileMode: TileMode.clamp,
            ),
            child: Transform.scale(
              scale: 1.12,
              child: image,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: cardTheme.backFaceImageOverlayGradient(),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(gradient: cardTheme.backFaceSheenGradient()),
        ),
        const CustomPaint(painter: _BrushedMetalPainter()),
      ],
    );
  }
}

class _BrushedMetalPainter extends CustomPainter {
  const _BrushedMetalPainter();

  static const _lineSpacing = 4.25;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()
      ..color = const Color(0x05FFFFFF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dark = Paint()
      ..color = const Color(0x04000000)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.07);
    final pad = math.max(size.width, size.height) * 0.35;
    canvas.translate(-size.width / 2, -size.height / 2);

    for (var y = -pad; y < size.height + pad; y += _lineSpacing) {
      final paint = ((y + pad) / _lineSpacing).floor().isEven ? light : dark;
      canvas.drawLine(Offset(-pad, y), Offset(size.width + pad, y), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrushedMetalPainter oldDelegate) => false;
}
