import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../shell/map_chrome_insets.dart';
import 'proximity_scanner_display.dart';

/// Guidance chrome (direction glow / proximity readout) for rotate or north-fixed follow.
class GuidanceOverlay extends StatelessWidget {
  const GuidanceOverlay({
    super.key,
    required this.rotateWithHeading,
  });

  /// True in AR rotate mode; false when the map is north-fixed.
  final bool rotateWithHeading;

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceSessionController>();
    if (!guidance.isActive) return const SizedBox.shrink();

    final remaining = guidance.remaining;
    final minutesLeft = remaining?.inMinutes.clamp(0, 999);
    final showDistance =
        guidance.showDistance && guidance.distanceLabel != null;
    final showSessionChrome = !showDistance;
    final topInset = MapChromeInsets.top(context);
    final focusFromBottom = rotateWithHeading
        ? MapConfig.mapboxRotateFocusFromBottom
        : 0.5;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GuidanceRangePainter(
                showRange: guidance.showNeedle && guidance.targetSite != null,
                centerDeg: guidance.rangeCenterScreenDeg(
                  rotateWithHeading: rotateWithHeading,
                ),
                rangeWidthDeg: guidance.rangeWidthDeg,
                focusFromBottom: focusFromBottom,
              ),
            ),
          ),
        ),
        if (showDistance)
          DraggableProximityScanner(
            key: ValueKey(guidance.session?.sessionId ?? 0),
            label: guidance.distanceLabel!,
            minutesLeft: minutesLeft,
            onStop: () => guidance.stop(),
          ),
        if (guidance.showRetargetBadge)
          Positioned(
            top: topInset + 56,
            left: 16,
            right: 16,
            child: Center(child: _RetargetBadge()),
          ),
        if (showSessionChrome)
          Positioned(
            top: topInset + 8,
            left: 16,
            right: 16,
            child: Center(
              child: _SessionChrome(
                title: guidance.kind?.toolName ?? 'Guidance',
                minutesLeft: minutesLeft,
                onStop: () => guidance.stop(),
              ),
            ),
          ),
      ],
    );
  }
}

class _RetargetBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          'Closer site sensed',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _SessionChrome extends StatelessWidget {
  const _SessionChrome({
    required this.title,
    required this.minutesLeft,
    required this.onStop,
  });

  final String title;
  final int? minutesLeft;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeLabel = minutesLeft == null ? '' : ' · ${minutesLeft}m';
    return Material(
      color: scheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(24),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4, top: 4, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$title$timeLabel',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: onStop,
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceRangePainter extends CustomPainter {
  _GuidanceRangePainter({
    required this.showRange,
    required this.centerDeg,
    required this.rangeWidthDeg,
    required this.focusFromBottom,
  });

  final bool showRange;
  final double centerDeg;
  final double rangeWidthDeg;
  final double focusFromBottom;

  static const _gold = Color(0xFFD4AF37);

  @override
  void paint(Canvas canvas, Size size) {
    if (!showRange) return;

    final center = Offset(
      size.width / 2,
      size.height * (1 - focusFromBottom),
    );
    final radius = 42.0;
    final width = rangeWidthDeg.clamp(1.0, 360.0);

    final ringPaint = Paint()
      ..color = _gold.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ringPaint);

    // Our 0° = device forward (up); Flutter arc 0° = east, clockwise.
    final startRad = (centerDeg - width / 2 - 90) * math.pi / 180;
    final sweepRad = width * math.pi / 180;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Soft outer glow — wider stroke, lower alpha when the range is broad.
    final glowAlpha = (0.12 + 0.28 * (1.0 - (width / 180).clamp(0.0, 1.0)))
        .clamp(0.12, 0.4);
    final glowStroke = 10.0 + 14.0 * (width / 180).clamp(0.0, 1.0);
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = _gold.withValues(alpha: glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = glowStroke
        ..strokeCap = StrokeCap.round,
    );

    // Core arc — sharper as exactness rises (narrower width).
    final coreAlpha = (0.55 + 0.35 * (1.0 - (width / 180).clamp(0.0, 1.0)))
        .clamp(0.55, 0.9);
    final coreStroke = 3.0 + 3.0 * (1.0 - (width / 180).clamp(0.0, 1.0));
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = _gold.withValues(alpha: coreAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = coreStroke
        ..strokeCap = StrokeCap.round,
    );

    // Faint filled wedge for broad ranges.
    if (width > 12) {
      final wedge = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, startRad, sweepRad, false)
        ..close();
      canvas.drawPath(
        wedge,
        Paint()
          ..color = _gold.withValues(alpha: 0.08 + 0.06 * (width / 180))
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuidanceRangePainter oldDelegate) {
    return oldDelegate.showRange != showRange ||
        oldDelegate.centerDeg != centerDeg ||
        oldDelegate.rangeWidthDeg != rangeWidthDeg ||
        oldDelegate.focusFromBottom != focusFromBottom;
  }
}
