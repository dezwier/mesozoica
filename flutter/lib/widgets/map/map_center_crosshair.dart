import 'package:flutter/material.dart';

/// Matches the location-puck gold accent.
const Color _centerCrosshairGold = Color(0xFFD4AF37);

/// Screen-fixed viewfinder for north-fixed map mode.
///
/// Stays locked to the viewport center (no geo updates → no pan jitter).
/// [IgnorePointer] keeps Mapbox location/site hits interactive underneath.
class MapCenterCrosshair extends StatelessWidget {
  const MapCenterCrosshair({super.key});

  static const double _size = 22;

  @override
  Widget build(BuildContext context) {
    final color = _centerCrosshairGold.withValues(alpha: 0.7);

    return IgnorePointer(
      child: Center(
        child: CustomPaint(
          size: const Size(_size, _size),
          painter: _MapCenterCrosshairPainter(color: color),
        ),
      ),
    );
  }
}

class _MapCenterCrosshairPainter extends CustomPainter {
  _MapCenterCrosshairPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.25
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1.25;

    canvas.drawCircle(center, radius, stroke);

    const gap = 3.5;
    final arm = radius - 1.5;
    canvas.drawLine(
      Offset(center.dx, center.dy - arm),
      Offset(center.dx, center.dy - gap),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + gap),
      Offset(center.dx, center.dy + arm),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx - arm, center.dy),
      Offset(center.dx - gap, center.dy),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx + gap, center.dy),
      Offset(center.dx + arm, center.dy),
      stroke,
    );

    canvas.drawCircle(center, 2.0, fill);
  }

  @override
  bool shouldRepaint(covariant _MapCenterCrosshairPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
