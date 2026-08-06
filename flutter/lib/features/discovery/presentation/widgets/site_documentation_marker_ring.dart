import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular marker frame whose gold arc shows aggregate documentation.
class SiteDocumentationMarkerRing extends StatelessWidget {
  const SiteDocumentationMarkerRing({
    super.key,
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.child,
    this.backgroundColor = Colors.white,
  });

  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: SiteDocumentationRingPainter(
        progress: progress,
        strokeWidth: strokeWidth,
        progressColor: progressColor,
        backgroundColor: backgroundColor,
      ),
      child: child,
    );
  }
}

class SiteDocumentationRingPainter extends CustomPainter {
  const SiteDocumentationRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.progressColor,
    required this.backgroundColor,
  });

  final double progress;
  final double strokeWidth;
  final Color progressColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final basePaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, basePaint);

    final value = progress.clamp(0.0, 1.0);
    if (value <= 0) return;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SiteDocumentationRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
