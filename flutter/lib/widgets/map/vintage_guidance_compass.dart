import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared brass palette for field instruments (compass / proximity).
abstract final class VintageInstrumentStyle {
  static const brassLight = Color(0xFF6B6354);
  static const brassMid = Color(0xFF3E382E);
  static const brassDark = Color(0xFF2A261F);
  static const brassRim = Color(0xFF8A8070);
  static const brassText = Color(0xFFC4B89A);
  static const brassMuted = Color(0xFF9A8F78);
  static const gold = Color(0xFFD4AF37);
  static const stop = Color(0xFFE07060);
  static const live = Color(0xFF7CFF9A);

  static const dialFace = Color(0xFF1A1712);
  static const dialFaceEdge = Color(0xFF2E2920);

  static const TextStyle mono = TextStyle(
    fontFamily: 'Courier',
    fontFamilyFallback: ['monospace'],
    letterSpacing: 1.2,
    fontWeight: FontWeight.w700,
    color: brassText,
  );
}

/// Vintage brass compass dial for Geo Compass and Site Navigator.
///
/// Optional [onStop] / [minutesLeft] show a session strip under the dial
/// (Geo Compass). Site Navigator keeps those on the proximity meter instead.
///
/// [centerDeg] is screen-relative (0 = up). [northDeg] places the N marker.
class VintageGuidanceCompass extends StatelessWidget {
  const VintageGuidanceCompass({
    super.key,
    required this.centerDeg,
    required this.rangeWidthDeg,
    required this.northDeg,
    this.minutesLeft,
    this.onStop,
    this.title = 'COMPASS',
  });

  final double centerDeg;
  final double rangeWidthDeg;
  final double northDeg;
  final int? minutesLeft;
  final VoidCallback? onStop;
  final String title;

  /// Outer housing diameter (dial + bezel).
  static const double size = 112;

  /// Extra height when timer / stop strip is shown under the dial.
  static const double sessionStripHeight = 28;

  @override
  Widget build(BuildContext context) {
    final time = minutesLeft == null ? '—' : '${minutesLeft}m';
    return SizedBox(
      width: size,
      height: size + (onStop != null ? sessionStripHeight : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.35, -0.4),
                  radius: 1.05,
                  colors: [
                    VintageInstrumentStyle.brassLight,
                    VintageInstrumentStyle.brassMid,
                    VintageInstrumentStyle.brassDark,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: VintageInstrumentStyle.brassRim,
                  width: 1.3,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 7,
                    child: Text(
                      title.toUpperCase(),
                      style: VintageInstrumentStyle.mono.copyWith(
                        fontSize: 6.5,
                        letterSpacing: 1.4,
                        color: VintageInstrumentStyle.brassMuted,
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(size, size),
                    painter: _VintageCompassPainter(
                      centerDeg: centerDeg,
                      rangeWidthDeg: rangeWidthDeg,
                      northDeg: northDeg,
                    ),
                  ),
                  ..._bezelRivets(),
                ],
              ),
            ),
          ),
          if (onStop != null) ...[
            const SizedBox(height: 6),
            _CompassSessionStrip(
              timeLabel: time,
              onStop: onStop!,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _bezelRivets() {
    final rivetR = size / 2 - 7;
    const rivetSize = 5.0;
    const angles = [-48.0, 48.0, 132.0, -132.0];
    return [
      for (final deg in angles)
        Transform.translate(
          offset: Offset(
            rivetR * math.sin(deg * math.pi / 180),
            -rivetR * math.cos(deg * math.pi / 180),
          ),
          child: Container(
            width: rivetSize,
            height: rivetSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFFB0A690), Color(0xFF5A5346)],
              ),
              border: Border.all(
                color: VintageInstrumentStyle.brassDark,
                width: 0.5,
              ),
            ),
          ),
        ),
    ];
  }
}

class _CompassSessionStrip extends StatelessWidget {
  const _CompassSessionStrip({
    required this.timeLabel,
    required this.onStop,
  });

  final String timeLabel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            VintageInstrumentStyle.brassLight,
            VintageInstrumentStyle.brassMid,
            VintageInstrumentStyle.brassDark,
          ],
        ),
        border: Border.all(
          color: VintageInstrumentStyle.brassRim,
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeLabel,
              style: VintageInstrumentStyle.mono.copyWith(fontSize: 11),
            ),
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VintageInstrumentStyle.live.withValues(alpha: 0.85),
                boxShadow: [
                  BoxShadow(
                    color:
                        VintageInstrumentStyle.live.withValues(alpha: 0.55),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onStop,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Text(
                  'STOP',
                  style: VintageInstrumentStyle.mono.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: VintageInstrumentStyle.stop,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VintageCompassPainter extends CustomPainter {
  _VintageCompassPainter({
    required this.centerDeg,
    required this.rangeWidthDeg,
    required this.northDeg,
  });

  final double centerDeg;
  final double rangeWidthDeg;
  final double northDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.width / 168.0; // proportions tuned at 168px
    final faceR = size.width / 2 - 14 * s - 6 * s;

    // Inner dial face.
    canvas.drawCircle(
      c,
      faceR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            VintageInstrumentStyle.dialFaceEdge,
            VintageInstrumentStyle.dialFace,
            const Color(0xFF0E0C09),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: faceR)),
    );
    canvas.drawCircle(
      c,
      faceR,
      Paint()
        ..color = const Color(0xFF4A4338)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * s,
    );

    // Aged glass sheen.
    canvas.drawCircle(
      c,
      faceR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.55),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: faceR)),
    );

    _drawTicks(canvas, c, faceR, s);
    _drawCardinals(canvas, c, faceR, s);
    _drawRange(canvas, c, faceR * 0.82, s);
    _drawHub(canvas, c, s);
  }

  void _drawTicks(Canvas canvas, Offset c, double faceR, double s) {
    final major = Paint()
      ..color = VintageInstrumentStyle.brassText.withValues(alpha: 0.85)
      ..strokeWidth = 1.4 * s
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = VintageInstrumentStyle.brassMuted.withValues(alpha: 0.55)
      ..strokeWidth = 0.9 * s
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 72; i++) {
      final deg = i * 5.0;
      final rad = _screenRad(deg + northDeg);
      final isCardinal = i % 18 == 0;
      final isMajor = i % 6 == 0;
      final inner =
          faceR - (isCardinal ? 14.0 : isMajor ? 10.0 : 6.0) * s;
      final outer = faceR - 2 * s;
      final paint = isMajor ? major : minor;
      canvas.drawLine(
        Offset(c.dx + inner * math.cos(rad), c.dy + inner * math.sin(rad)),
        Offset(c.dx + outer * math.cos(rad), c.dy + outer * math.sin(rad)),
        paint,
      );
    }
  }

  void _drawCardinals(Canvas canvas, Offset c, double faceR, double s) {
    const labels = ['N', 'E', 'S', 'W'];
    const angles = [0.0, 90.0, 180.0, 270.0];
    for (var i = 0; i < 4; i++) {
      final rad = _screenRad(angles[i] + northDeg);
      final r = faceR - 26 * s;
      final pos = Offset(
        c.dx + r * math.cos(rad),
        c.dy + r * math.sin(rad),
      );
      final isNorth = labels[i] == 'N';
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'tt_ramilas',
            fontSize: (isNorth ? 16 : 13) * s,
            fontWeight: FontWeight.w700,
            color: isNorth
                ? VintageInstrumentStyle.gold
                : VintageInstrumentStyle.brassText,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawRange(Canvas canvas, Offset c, double radius, double s) {
    final width = rangeWidthDeg.clamp(1.0, 360.0);
    final startRad = _screenRad(centerDeg - width / 2);
    final sweepRad = width * math.pi / 180;
    final rect = Rect.fromCircle(center: c, radius: radius);

    final glowAlpha =
        (0.14 + 0.3 * (1.0 - (width / 180).clamp(0.0, 1.0))).clamp(0.14, 0.44);
    final glowStroke = (12.0 + 10.0 * (width / 180).clamp(0.0, 1.0)) * s;
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = VintageInstrumentStyle.gold.withValues(alpha: glowAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = glowStroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * s),
    );

    final coreAlpha =
        (0.6 + 0.35 * (1.0 - (width / 180).clamp(0.0, 1.0))).clamp(0.6, 0.95);
    final coreStroke = (3.5 + 3.5 * (1.0 - (width / 180).clamp(0.0, 1.0))) * s;
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = VintageInstrumentStyle.gold.withValues(alpha: coreAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = coreStroke
        ..strokeCap = StrokeCap.round,
    );

    // Needle tip at range center.
    final tipRad = _screenRad(centerDeg);
    final tip = Offset(
      c.dx + radius * math.cos(tipRad),
      c.dy + radius * math.sin(tipRad),
    );
    final tipR = 3.5 * s;
    canvas.drawCircle(
      tip,
      tipR,
      Paint()..color = VintageInstrumentStyle.gold,
    );
    canvas.drawCircle(
      tip,
      tipR,
      Paint()
        ..color = const Color(0xFFF5E6A8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * s,
    );

    if (width > 10) {
      final wedge = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, startRad, sweepRad, false)
        ..close();
      canvas.drawPath(
        wedge,
        Paint()
          ..color = VintageInstrumentStyle.gold
              .withValues(alpha: 0.07 + 0.05 * (width / 180))
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawHub(Canvas canvas, Offset c, double s) {
    final hubR = 8 * s;
    canvas.drawCircle(
      c,
      hubR,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFB0A690), Color(0xFF5A5346), Color(0xFF2A261F)],
        ).createShader(Rect.fromCircle(center: c, radius: hubR)),
    );
    canvas.drawCircle(
      c,
      3 * s,
      Paint()..color = VintageInstrumentStyle.gold.withValues(alpha: 0.9),
    );
  }

  /// Convert compass degrees (0 = up, clockwise) to canvas radians.
  static double _screenRad(double deg) => (deg - 90) * math.pi / 180;

  @override
  bool shouldRepaint(covariant _VintageCompassPainter oldDelegate) {
    return oldDelegate.centerDeg != centerDeg ||
        oldDelegate.rangeWidthDeg != rangeWidthDeg ||
        oldDelegate.northDeg != northDeg;
  }
}
