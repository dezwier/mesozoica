import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Line icons engraved in the museum-card style.
enum MuseumGlyph {
  skull,
  bone,
  landscape,
  tool,
  terrain,
  meat,
  mass,
  length,
  layers,
  shield,
  pie,
  dial,
}

MuseumGlyph museumGlyphForAttribute(String label) {
  switch (label.trim().toLowerCase()) {
    case 'period':
      return MuseumGlyph.terrain;
    case 'diet':
      return MuseumGlyph.meat;
    case 'mass':
      return MuseumGlyph.mass;
    case 'length':
      return MuseumGlyph.length;
    case 'category':
    case 'sub category':
      return MuseumGlyph.layers;
    case 'preservation':
    case 'preservation quality':
      return MuseumGlyph.shield;
    case 'completeness':
      return MuseumGlyph.pie;
    default:
      return MuseumGlyph.dial;
  }
}

class MuseumGlyphIcon extends StatelessWidget {
  const MuseumGlyphIcon({
    super.key,
    required this.glyph,
    this.size = 22,
    this.color,
  });

  final MuseumGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? DinoCardTheme.of(context).cardAccent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MuseumGlyphPainter(glyph: glyph, color: resolved),
      ),
    );
  }
}

class _MuseumGlyphPainter extends CustomPainter {
  const _MuseumGlyphPainter({required this.glyph, required this.color});

  final MuseumGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 24;
    canvas.save();
    canvas.scale(unit);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    switch (glyph) {
      case MuseumGlyph.skull:
        _skull(canvas, stroke, fill);
      case MuseumGlyph.bone:
        _bone(canvas, stroke, fill);
      case MuseumGlyph.landscape:
        _landscape(canvas, stroke, fill);
      case MuseumGlyph.tool:
        _tool(canvas, stroke);
      case MuseumGlyph.terrain:
        _terrain(canvas, stroke, fill);
      case MuseumGlyph.meat:
        _meat(canvas, stroke, fill);
      case MuseumGlyph.mass:
        _mass(canvas, stroke, fill);
      case MuseumGlyph.length:
        _length(canvas, stroke, fill);
      case MuseumGlyph.layers:
        _layers(canvas, stroke);
      case MuseumGlyph.shield:
        _shield(canvas, stroke, fill);
      case MuseumGlyph.pie:
        _pie(canvas, stroke, fill);
      case MuseumGlyph.dial:
        _dial(canvas, stroke);
    }
    canvas.restore();
  }

  void _skull(Canvas canvas, Paint stroke, Paint fill) {
    final cranium = Path()..addOval(Rect.fromLTWH(5, 3.2, 14, 12.2));
    canvas.drawPath(cranium, fill);
    canvas.drawPath(cranium, stroke);
    canvas.drawCircle(const Offset(9.2, 9.2), 1.15, stroke);
    canvas.drawCircle(const Offset(14.8, 9.2), 1.15, stroke);
    final nose = Path()
      ..moveTo(12, 11.2)
      ..lineTo(10.8, 13.2)
      ..lineTo(13.2, 13.2)
      ..close();
    canvas.drawPath(nose, stroke);
    final jaw = Path()
      ..moveTo(7.4, 14.6)
      ..quadraticBezierTo(12, 20.4, 16.6, 14.6);
    canvas.drawPath(jaw, stroke);
    canvas.drawLine(const Offset(9.2, 16.6), const Offset(9.2, 18.2), stroke);
    canvas.drawLine(const Offset(12, 17.1), const Offset(12, 18.6), stroke);
    canvas.drawLine(const Offset(14.8, 16.6), const Offset(14.8, 18.2), stroke);
  }

  void _bone(Canvas canvas, Paint stroke, Paint fill) {
    canvas.save();
    canvas.translate(12, 12);
    canvas.rotate(-0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5.2, -1.5, 10.4, 3),
        const Radius.circular(1.5),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5.2, -1.5, 10.4, 3),
        const Radius.circular(1.5),
      ),
      stroke,
    );
    canvas.drawCircle(const Offset(-5.4, -1.6), 2.1, fill);
    canvas.drawCircle(const Offset(-5.4, 1.6), 2.1, fill);
    canvas.drawCircle(const Offset(5.4, -1.6), 2.1, fill);
    canvas.drawCircle(const Offset(5.4, 1.6), 2.1, fill);
    canvas.drawCircle(const Offset(-5.4, -1.6), 2.1, stroke);
    canvas.drawCircle(const Offset(-5.4, 1.6), 2.1, stroke);
    canvas.drawCircle(const Offset(5.4, -1.6), 2.1, stroke);
    canvas.drawCircle(const Offset(5.4, 1.6), 2.1, stroke);
    canvas.restore();
  }

  void _landscape(Canvas canvas, Paint stroke, Paint fill) {
    final hills = Path()
      ..moveTo(2.5, 16.5)
      ..quadraticBezierTo(7, 9, 11, 14)
      ..quadraticBezierTo(15, 8.5, 21.5, 16.5)
      ..lineTo(21.5, 20)
      ..lineTo(2.5, 20)
      ..close();
    canvas.drawPath(hills, fill);
    canvas.drawPath(hills, stroke);
    canvas.drawCircle(const Offset(16.5, 6.2), 1.7, stroke);
  }

  void _tool(Canvas canvas, Paint stroke) {
    canvas.drawCircle(const Offset(8.2, 8.2), 3.3, stroke);
    canvas.drawLine(const Offset(10.6, 10.6), const Offset(18.5, 18.5), stroke);
    canvas.drawLine(const Offset(16.2, 16.4), const Offset(19.4, 15.2), stroke);
    canvas.drawLine(const Offset(15.4, 19.2), const Offset(16.6, 16.2), stroke);
  }

  Paint _solid(Paint stroke) {
    return Paint()
      ..color = stroke.color
      ..style = PaintingStyle.fill;
  }

  void _terrain(Canvas canvas, Paint stroke, Paint _) {
    final solid = _solid(stroke);
    final peaks = Path()
      ..moveTo(1.2, 20.2)
      ..lineTo(6.6, 9.2)
      ..lineTo(10.6, 14.6)
      ..lineTo(12.4, 12.2)
      ..lineTo(17.2, 4.2)
      ..lineTo(22.8, 20.2)
      ..close();
    canvas.drawPath(peaks, solid);
    canvas.drawPath(peaks, stroke);
  }

  void _meat(Canvas canvas, Paint stroke, Paint _) {
    final solid = _solid(stroke);
    final ham = Path()
      ..moveTo(1.2, 12.4)
      ..cubicTo(0.6, 6.2, 5.4, 3.6, 9.6, 5.2)
      ..cubicTo(12.4, 6.2, 13.2, 8.6, 13.6, 10.2)
      ..lineTo(18.4, 8.6)
      ..lineTo(20.6, 6.4)
      ..cubicTo(23.4, 6.8, 23.6, 10.6, 21.2, 11.8)
      ..lineTo(18.6, 12.6)
      ..lineTo(13.8, 13.4)
      ..cubicTo(13.2, 17.6, 9.4, 20.6, 5.2, 19.2)
      ..cubicTo(1.4, 17.8, 0.4, 15.2, 1.2, 12.4)
      ..close();
    canvas.drawPath(ham, solid);
    canvas.drawPath(ham, stroke);
  }

  void _mass(Canvas canvas, Paint stroke, Paint _) {
    final solid = _solid(stroke);
    canvas.drawArc(
      const Rect.fromLTWH(8.4, 1.6, 7.2, 5.6),
      3.15,
      3.15,
      false,
      stroke,
    );
    final body = Path()
      ..moveTo(6.6, 6.8)
      ..lineTo(17.4, 6.8)
      ..lineTo(20.8, 21.0)
      ..lineTo(3.2, 21.0)
      ..close();
    canvas.drawPath(body, solid);
    canvas.drawPath(body, stroke);
    final mark = Paint()
      ..color = const Color(0xFFF6E7D4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(9.0, 12.2), const Offset(15.0, 12.2), mark);
    canvas.drawLine(const Offset(12, 12.2), const Offset(12, 17.2), mark);
  }

  void _length(Canvas canvas, Paint stroke, Paint _) {
    final solid = _solid(stroke);
    final body = Path()
      ..moveTo(0.4, 16.4)
      ..lineTo(8.2, 14.6)
      ..lineTo(11.4, 13.2)
      ..lineTo(14.0, 8.6)
      ..lineTo(16.2, 6.2)
      ..lineTo(18.8, 3.4)
      ..lineTo(23.4, 2.8)
      ..lineTo(22.6, 5.2)
      ..lineTo(19.2, 5.8)
      ..lineTo(17.2, 8.0)
      ..lineTo(14.8, 12.0)
      ..lineTo(11.0, 14.6)
      ..lineTo(6.4, 16.6)
      ..lineTo(0.4, 18.0)
      ..close();
    canvas.drawPath(body, solid);
    canvas.drawPath(body, stroke);
    final leg = Path()
      ..moveTo(8.4, 15.6)
      ..lineTo(10.2, 15.4)
      ..lineTo(9.4, 21.6)
      ..lineTo(7.4, 21.6)
      ..close();
    final leg2 = Path()
      ..moveTo(11.6, 14.8)
      ..lineTo(13.4, 14.6)
      ..lineTo(13.8, 21.4)
      ..lineTo(11.6, 21.4)
      ..close();
    canvas.drawPath(leg, solid);
    canvas.drawPath(leg2, solid);
    final arm = Path()
      ..moveTo(15.0, 10.4)
      ..lineTo(17.8, 11.8)
      ..lineTo(17.4, 12.8)
      ..lineTo(14.6, 11.4)
      ..close();
    canvas.drawPath(arm, solid);
  }

  void _layers(Canvas canvas, Paint stroke) {
    for (var i = 0; i < 3; i++) {
      final top = 4.0 + i * 5.6;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(3.5, top, 17, 4.2),
          const Radius.circular(1.4),
        ),
        stroke,
      );
    }
  }

  void _shield(Canvas canvas, Paint stroke, Paint fill) {
    final shield = Path()
      ..moveTo(12, 3.2)
      ..lineTo(19.2, 6.2)
      ..lineTo(19.2, 12)
      ..quadraticBezierTo(19.2, 18.2, 12, 21)
      ..quadraticBezierTo(4.8, 18.2, 4.8, 12)
      ..lineTo(4.8, 6.2)
      ..close();
    canvas.drawPath(shield, fill);
    canvas.drawPath(shield, stroke);
  }

  void _pie(Canvas canvas, Paint stroke, Paint fill) {
    final arc = Path()
      ..moveTo(12, 12)
      ..arcTo(const Rect.fromLTWH(4, 4, 16, 16), -1.2, 2.2, false)
      ..close();
    canvas.drawPath(arc, fill);
    canvas.drawCircle(const Offset(12, 12), 8, stroke);
    canvas.drawPath(arc, stroke);
  }

  void _dial(Canvas canvas, Paint stroke) {
    canvas.drawCircle(const Offset(12, 12), 8, stroke);
    canvas.drawLine(const Offset(12, 12), const Offset(16.2, 8.4), stroke);
    canvas.drawCircle(const Offset(12, 12), 1.1, stroke);
  }

  @override
  bool shouldRepaint(covariant _MuseumGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.color != color;
  }
}
