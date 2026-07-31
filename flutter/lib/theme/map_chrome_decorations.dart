import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'map_chrome_theme.dart';

/// Shared vintage decorations for map chrome (brass rims, leather, parchment).
abstract final class MapChromeDecorations {
  /// Circular leather dial with a muted brass rim (FABs, notification).
  static BoxDecoration brassCircle({
    required Color dialFace,
    double rimWidth = MapChromeTheme.chromeBorderWidth,
  }) {
    return BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.25, -0.3),
        radius: 1.15,
        colors: [
          Color.lerp(dialFace, MapChromeTheme.leatherSoftHighlight, 0.35)!,
          dialFace,
          Color.lerp(dialFace, MapChromeTheme.leatherSoft, 0.4)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ),
      border: Border.all(
        color: MapChromeTheme.chromeBorder,
        width: rimWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 5,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Dark leather / oxidized metal fill for bars and pills.
  static BoxDecoration leatherPanel({
    required BorderRadius borderRadius,
    double borderWidth = MapChromeTheme.chromeBorderWidth,
    bool soft = false,
  }) {
    final highlight =
        soft ? MapChromeTheme.leatherSoftHighlight : MapChromeTheme.leatherHighlight;
    final mid = soft ? MapChromeTheme.leatherSoftMid : MapChromeTheme.leatherMid;
    final base = soft ? MapChromeTheme.leatherSoft : MapChromeTheme.leather;
    return BoxDecoration(
      borderRadius: borderRadius,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [highlight, mid, base],
        stops: const [0.0, 0.4, 1.0],
      ),
      border: Border.all(
        color: MapChromeTheme.chromeBorder,
        width: borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: soft ? 0.28 : 0.35),
          blurRadius: soft ? 6 : 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  /// Soft parchment fill for labels and selected toggle segments.
  static BoxDecoration parchmentPanel({
    required BorderRadius borderRadius,
  }) {
    return BoxDecoration(
      borderRadius: borderRadius,
      // Near-flat: only a whisper of top→bottom warmth.
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          MapChromeTheme.creamCard,
          MapChromeTheme.parchment,
        ],
      ),
      border: Border.all(
        color: MapChromeTheme.parchmentEdge.withValues(alpha: 0.45),
        width: 0.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.14),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }
}

/// Paints a beveled brass ring around a circular dial (outer rim highlight).
class BrassRimPainter extends CustomPainter {
  const BrassRimPainter({this.rimFraction = 0.1});

  final double rimFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.shortestSide / 2;
    final rimW = outer * rimFraction;
    final mid = outer - rimW / 2;

    final brassShader = ui.Gradient.sweep(
      center,
      [
        MapChromeTheme.brassMid,
        MapChromeTheme.brassLight,
        MapChromeTheme.brassMid,
        MapChromeTheme.brassDark,
        MapChromeTheme.brassMid,
        MapChromeTheme.brassLight,
        MapChromeTheme.brassMid,
      ],
      [0.0, 0.18, 0.38, 0.55, 0.72, 0.88, 1.0],
      TileMode.clamp,
      -math.pi / 4,
    );

    final rimPaint = Paint()
      ..shader = brassShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimW;

    canvas.drawCircle(center, mid, rimPaint);

    // Soft inner edge
    canvas.drawCircle(
      center,
      outer - rimW,
      Paint()
        ..color = MapChromeTheme.brassDark.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // Soft outer highlight
    canvas.drawCircle(
      center,
      outer - 0.5,
      Paint()
        ..color = MapChromeTheme.brassLight.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant BrassRimPainter oldDelegate) =>
      oldDelegate.rimFraction != rimFraction;
}

/// Subtle parchment grain overlay (soft noise dots).
class ParchmentGrainPainter extends CustomPainter {
  const ParchmentGrainPainter({this.alpha = 0.06});

  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MapChromeTheme.brownText.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    final rng = math.Random(42);
    final count = (size.width * size.height / 28).round().clamp(8, 120);
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), rng.nextDouble() * 0.8 + 0.3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParchmentGrainPainter oldDelegate) =>
      oldDelegate.alpha != alpha;
}
