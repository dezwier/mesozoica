import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/map_chrome_theme.dart';

/// Curved trail of gold sparkles from [from] to [to] (overlay-local coords).
class XpMagicStringPainter extends CustomPainter {
  XpMagicStringPainter({
    required this.from,
    required this.to,
    required this.progress,
    required this.seed,
  });

  final Offset from;
  final Offset to;
  final double progress;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final mid = Offset(
      (from.dx + to.dx) / 2 + (to.dx - from.dx) * 0.15,
      math.min(from.dy, to.dy) - 28,
    );
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final length = metric.length;
    if (length <= 0) return;

    final head = (progress * length).clamp(0.0, length);
    final trailStart = (head - length * 0.55).clamp(0.0, length);

    // Soft glowing ribbon behind the particles.
    final ribbon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        from,
        to,
        [
          MapChromeTheme.gold.withValues(alpha: 0.0),
          MapChromeTheme.goldBright.withValues(alpha: 0.55 * progress),
          MapChromeTheme.gold.withValues(alpha: 0.15 * progress),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(
      metric.extractPath(trailStart, head),
      ribbon,
    );

    final rng = math.Random(seed);
    const particleCount = 18;
    for (var i = 0; i < particleCount; i++) {
      final t = i / (particleCount - 1);
      final dist = trailStart + (head - trailStart) * t;
      if (dist > head || dist < trailStart) continue;
      final tangent = metric.getTangentForOffset(dist);
      if (tangent == null) continue;

      final age = 1.0 - ((head - dist) / math.max(1.0, head - trailStart));
      final flicker = 0.65 + 0.35 * math.sin(progress * 12 + i);
      final radius = (1.2 + rng.nextDouble() * 2.4) * (0.4 + age * 0.9);
      final alpha = (0.25 + age * 0.75) * flicker * progress.clamp(0.0, 1.0);

      final perp = Offset(-tangent.vector.dy, tangent.vector.dx);
      final jitter = (rng.nextDouble() - 0.5) * 6 * (1 - age);
      final pos = tangent.position + perp * jitter;

      final paint = Paint()
        ..color = MapChromeTheme.goldBright.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawCircle(pos, radius, paint);

      // Tiny bright core.
      canvas.drawCircle(
        pos,
        radius * 0.45,
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.85),
      );
    }

    // Landing burst near the XP bar.
    if (progress > 0.82) {
      final burst = ((progress - 0.82) / 0.18).clamp(0.0, 1.0);
      final burstPaint = Paint()
        ..color = MapChromeTheme.goldBright.withValues(alpha: 0.55 * (1 - burst))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(to, 4 + burst * 14, burstPaint);
      canvas.drawCircle(
        to,
        2 + burst * 6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7 * (1 - burst)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant XpMagicStringPainter oldDelegate) {
    return oldDelegate.from != from ||
        oldDelegate.to != to ||
        oldDelegate.progress != progress ||
        oldDelegate.seed != seed;
  }
}
