import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/catalog_mode_controller.dart';
import '../../theme/map_chrome_theme.dart';

class CatalogModeToggle extends StatelessWidget {
  const CatalogModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CatalogModeController>(
      builder: (context, controller, _) {
        final selected = controller.dataSource;
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: MapChromeTheme.darkGlassSoft,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Segment(
                label: 'Archive',
                selected: selected == CatalogDataSource.archive,
                onTap: () =>
                    controller.setDataSource(CatalogDataSource.archive),
              ),
              _Segment(
                label: 'Field',
                selected: selected == CatalogDataSource.field,
                showFootprint: true,
                onTap: () => controller.setDataSource(CatalogDataSource.field),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.showFootprint = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showFootprint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? MapChromeTheme.cream : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showFootprint && selected) ...[
              CustomPaint(
                size: const Size(12, 12),
                painter: _DinoFootprintPainter(
                  color: MapChromeTheme.brownText,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? MapChromeTheme.brownText : Colors.white,
                fontSize: 12,
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

/// Simple three-toed dinosaur footprint for the Field segment.
class _DinoFootprintPainter extends CustomPainter {
  _DinoFootprintPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.62;

    // Heel pad
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: w * 0.42,
        height: h * 0.38,
      ),
      paint,
    );

    // Three toes
    for (final angle in [-0.55, 0.0, 0.55]) {
      final tip = Offset(
        cx + math.sin(angle) * w * 0.38,
        cy - math.cos(angle) * h * 0.52,
      );
      final path = Path()
        ..moveTo(cx + math.sin(angle) * w * 0.08, cy - h * 0.08)
        ..quadraticBezierTo(
          tip.dx,
          tip.dy + h * 0.08,
          tip.dx,
          tip.dy,
        )
        ..quadraticBezierTo(
          tip.dx + math.cos(angle) * w * 0.1,
          tip.dy + h * 0.12,
          cx + math.sin(angle) * w * 0.14,
          cy - h * 0.02,
        )
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawCircle(tip, w * 0.09, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DinoFootprintPainter oldDelegate) =>
      oldDelegate.color != color;
}
