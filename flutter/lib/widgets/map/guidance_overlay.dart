import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/guidance_session_controller.dart';

/// Rotation-mode guidance chrome: needle, distance chip, retarget badge, timer.
class GuidanceOverlay extends StatelessWidget {
  const GuidanceOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final guidance = context.watch<GuidanceSessionController>();
    if (!guidance.isActive) return const SizedBox.shrink();

    final remaining = guidance.remaining;
    final minutesLeft = remaining?.inMinutes.clamp(0, 999);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GuidanceNeedlePainter(
                showNeedle: guidance.showNeedle && guidance.targetSite != null,
                needleDeg: guidance.needleScreenDeg,
                focusFromBottom: MapConfig.mapboxRotateFocusFromBottom,
              ),
            ),
          ),
        ),
        if (guidance.showDistance && guidance.distanceLabel != null)
          Align(
            alignment: Alignment(
              0,
              1 - (MapConfig.mapboxRotateFocusFromBottom * 2) + 0.12,
            ),
            child: _DistanceChip(label: guidance.distanceLabel!),
          ),
        if (guidance.showRetargetBadge)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 72),
                child: _RetargetBadge(),
              ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _SessionChrome(
                title: guidance.kind?.toolName ?? 'Guidance',
                minutesLeft: minutesLeft,
                onStop: () => guidance.stop(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DistanceChip extends StatelessWidget {
  const _DistanceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
        ),
      ),
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

class _GuidanceNeedlePainter extends CustomPainter {
  _GuidanceNeedlePainter({
    required this.showNeedle,
    required this.needleDeg,
    required this.focusFromBottom,
  });

  final bool showNeedle;
  final double needleDeg;
  final double focusFromBottom;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showNeedle) return;

    final center = Offset(
      size.width / 2,
      size.height * (1 - focusFromBottom),
    );
    final radius = 42.0;

    final ringPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ringPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(needleDeg * math.pi / 180);

    final needlePaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, -radius - 6)
      ..lineTo(7, -radius + 14)
      ..lineTo(0, -radius + 8)
      ..lineTo(-7, -radius + 14)
      ..close();
    canvas.drawPath(path, needlePaint);

    final tailPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(0, radius * 0.45), tailPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GuidanceNeedlePainter oldDelegate) {
    return oldDelegate.showNeedle != showNeedle ||
        oldDelegate.needleDeg != needleDeg ||
        oldDelegate.focusFromBottom != focusFromBottom;
  }
}
