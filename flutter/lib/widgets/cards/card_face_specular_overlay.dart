import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shape of clipping for gloss within the overlaid rectangle.
enum SpecularOverlayClip {
  /// Rounded rectangle (all corners use [cornerRadius]).
  fullRoundedRect,

  /// Top corners rounded; bottom corners square ([cornerRadius]) — image strip onto text.
  roundedTopStrip,
}

/// Translucent specular streak tied to uninterrupted card spin [motionRadians].
///
/// Uses the raw flip controller radians so phase is smooth across arbitrarily many turns
/// (`sin` / `cos` repeat every full turn). Drawn SrcOver on top of imagery.
///
/// Painted in both light and dark themes.
class CardFaceSpecularOverlay extends StatelessWidget {
  const CardFaceSpecularOverlay({
    super.key,
    required this.motionRadians,
    required this.cornerRadius,
    this.clipShape = SpecularOverlayClip.fullRoundedRect,
  });

  /// Unwrapped flip angle (same value as [AnimationController] driving the card).
  final double motionRadians;
  final double cornerRadius;
  final SpecularOverlayClip clipShape;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _CardFaceSpecularPainter(
            motionRadians: motionRadians,
            cornerRadius: cornerRadius,
            clipShape: clipShape,
          ),
        ),
      ),
    );
  }
}

class _CardFaceSpecularPainter extends CustomPainter {
  _CardFaceSpecularPainter({
    required this.motionRadians,
    required this.cornerRadius,
    required this.clipShape,
  });

  final double motionRadians;
  final double cornerRadius;
  final SpecularOverlayClip clipShape;

  /// Periodic in the spin angle; same brightness class whether spin is wound many times.
  static double _faceFactor(double radians) =>
      math.pow(math.cos(radians).clamp(-1.0, 1.0).abs(), 0.32).toDouble();

  static const double _kMainSweepX = 0.82;
  static const double _kMainSweepY = 0.26;
  static const double _kRotateDrive = 0.68;

  /// Default hotspot sits past center, toward one lateral edge (upper-side key light).
  static const double _kGlareAnchorX = 0.69;
  static const double _kGlareAnchorY = 0.26;

  static RRect _clipRRect(Size size, double rounded, SpecularOverlayClip clip) {
    final rect = Offset.zero & size;
    switch (clip) {
      case SpecularOverlayClip.fullRoundedRect:
        return RRect.fromRectAndRadius(
          rect,
          Radius.circular(rounded),
        );
      case SpecularOverlayClip.roundedTopStrip:
        return RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(rounded),
          topRight: Radius.circular(rounded),
          bottomRight: Radius.zero,
          bottomLeft: Radius.zero,
        );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rounded = cornerRadius.clamp(0.0, 999.0);
    final rrect = _clipRRect(size, rounded, clipShape);

    final rawFace = _faceFactor(motionRadians);
    final strength = rawFace.clamp(0.22, 1.0);
    final peakAlpha = strength * 0.2;

    final hi = Color.lerp(Colors.white, const Color(0xFFB8D9FF), 0.12)!
        .withValues(alpha: peakAlpha);

    canvas.save();
    canvas.clipRRect(rrect);

    _paintMainBand(canvas, size: size, hi: hi, peakAlpha: peakAlpha);

    canvas.restore();
  }

  void _paintMainBand(
    Canvas canvas, {
    required Size size,
    required Color hi,
    required double peakAlpha,
  }) {
    final cx =
        size.width * (_kGlareAnchorX + math.sin(motionRadians) * _kMainSweepX);
    final cy = size.height *
        (_kGlareAnchorY + math.cos(motionRadians * 1.05) * _kMainSweepY);

    canvas.save();
    canvas.translate(cx, cy);
    // Slightly steeper diagonal so the band reads more along the side / corner.
    canvas.rotate(math.pi / 3.55 + motionRadians * _kRotateDrive);
    canvas.translate(-cx, -cy);

    final span = math.max(size.width, size.height) * 2.45;
    final band = Rect.fromCenter(
      center: Offset(cx, cy),
      width: span,
      height: span,
    );

    final p0 = Offset(
      band.left + band.width * 0.02,
      band.top + band.height * 0.1,
    );
    final p1 = Offset(
      band.right - band.width * 0.01,
      band.bottom - band.height * 0.08,
    );

    final core = peakAlpha.clamp(0.0, 0.82);

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        p0,
        p1,
        [
          Colors.transparent,
          hi.withValues(alpha: core * 0.15),
          hi.withValues(alpha: core * 0.58),
          hi.withValues(alpha: core * 1.0),
          hi.withValues(alpha: core * 0.62),
          hi.withValues(alpha: core * 0.12),
          Colors.transparent,
        ],
        const [0.0, 0.32, 0.42, 0.485, 0.54, 0.64, 1.0],
      );

    canvas.drawRect(Rect.fromLTWH(-span, -span, span * 3, span * 3), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CardFaceSpecularPainter oldDelegate) {
    return oldDelegate.motionRadians != motionRadians ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.clipShape != clipShape;
  }
}

/// Height of a top-aligned 1:1 image band given column constraints.
double specularTopSquareImageBandHeight(BoxConstraints c) {
  if (!c.hasBoundedWidth || c.maxWidth <= 0) return 0;
  if (!c.hasBoundedHeight || c.maxHeight.isInfinite) {
    return c.maxWidth;
  }
  return math.min(c.maxWidth, c.maxHeight);
}
