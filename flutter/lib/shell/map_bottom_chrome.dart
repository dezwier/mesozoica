import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/map_chrome_theme.dart';
import 'map_chrome_insets.dart';

/// Frosted bottom entry points: Sites, Fossils, Dinosaurs, Tools.
class MapBottomChrome extends StatelessWidget {
  const MapBottomChrome({
    super.key,
    required this.onOpenSites,
    required this.onOpenFossils,
    required this.onOpenDinosaurs,
    required this.onOpenTools,
  });

  final VoidCallback onOpenSites;
  final VoidCallback onOpenFossils;
  final VoidCallback onOpenDinosaurs;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Container(
                height: MapChromeInsets.bottomRowHeight - 6,
                decoration: BoxDecoration(
                  color: MapChromeTheme.darkGlass,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavItem(
                        label: 'Sites',
                        onTap: onOpenSites,
                        painter: _RockIconPainter(),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        label: 'Fossils',
                        onTap: onOpenFossils,
                        painter: _BoneIconPainter(),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        label: 'Dinosaurs',
                        onTap: onOpenDinosaurs,
                        painter: _SkullIconPainter(),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        label: 'Tools',
                        onTap: onOpenTools,
                        painter: _ToolsIconPainter(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.onTap,
    required this.painter,
  });

  final String label;
  final VoidCallback onTap;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    const color = MapChromeTheme.cream;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: MapChromeInsets.bottomIconSize,
              height: MapChromeInsets.bottomIconSize,
              child: CustomPaint(
                painter: _TintedPainter(painter, color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Applies a stroke/fill color to painters that use [Paint] with default black.
class _TintedPainter extends CustomPainter {
  _TintedPainter(this.inner, this.color);

  final CustomPainter inner;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (inner is _ChromeLineIconPainter) {
      (inner as _ChromeLineIconPainter).paintWith(canvas, size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TintedPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.inner != inner;
}

abstract class _ChromeLineIconPainter extends CustomPainter {
  void paintWith(Canvas canvas, Size size, Paint paint);

  @override
  void paint(Canvas canvas, Size size) {
    paintWith(
      canvas,
      size,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RockIconPainter extends _ChromeLineIconPainter {
  @override
  void paintWith(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.18, h * 0.72)
      ..lineTo(w * 0.28, h * 0.38)
      ..lineTo(w * 0.48, h * 0.28)
      ..lineTo(w * 0.72, h * 0.36)
      ..lineTo(w * 0.82, h * 0.62)
      ..lineTo(w * 0.68, h * 0.78)
      ..lineTo(w * 0.32, h * 0.78)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(w * 0.38, h * 0.48),
      Offset(w * 0.55, h * 0.58),
      paint,
    );
  }
}

class _BoneIconPainter extends _ChromeLineIconPainter {
  @override
  void paintWith(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-math.pi / 5);
    canvas.translate(-cx, -cy);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: w * 0.12,
          height: h * 0.55,
        ),
        const Radius.circular(4),
      ),
      paint,
    );
    for (final y in [h * 0.28, h * 0.72]) {
      canvas.drawCircle(Offset(cx - w * 0.12, y), w * 0.1, paint);
      canvas.drawCircle(Offset(cx + w * 0.12, y), w * 0.1, paint);
    }
    canvas.restore();
  }
}

class _SkullIconPainter extends _ChromeLineIconPainter {
  @override
  void paintWith(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final head = Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.42),
          width: w * 0.58,
          height: h * 0.52,
        ),
      );
    canvas.drawPath(head, paint);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.38, h * 0.42),
        width: w * 0.14,
        height: h * 0.16,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.62, h * 0.42),
        width: w * 0.14,
        height: h * 0.16,
      ),
      paint,
    );
    // Snout / jaw
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.34, h * 0.58, w * 0.32, h * 0.22),
        const Radius.circular(4),
      ),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.42, h * 0.7),
      Offset(w * 0.42, h * 0.78),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.58, h * 0.7),
      Offset(w * 0.58, h * 0.78),
      paint,
    );
  }
}

class _ToolsIconPainter extends _ChromeLineIconPainter {
  @override
  void paintWith(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    final handlePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawTool(double angle) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      canvas.translate(-cx, -cy);
      canvas.drawLine(
        Offset(cx, h * 0.22),
        Offset(cx, h * 0.72),
        handlePaint,
      );
      final head = Path()
        ..moveTo(cx - w * 0.18, h * 0.28)
        ..lineTo(cx + w * 0.18, h * 0.28)
        ..lineTo(cx + w * 0.12, h * 0.4)
        ..lineTo(cx - w * 0.12, h * 0.4)
        ..close();
      canvas.drawPath(head, paint);
      canvas.restore();
    }

    drawTool(-math.pi / 5);
    drawTool(math.pi / 5);
  }
}
