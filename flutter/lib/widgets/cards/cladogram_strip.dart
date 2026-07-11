import 'package:flutter/material.dart';

import '../../theme/dino_card_theme.dart';

/// Branching phylogenetic tree matching the reference card back.
class CladogramStrip extends StatelessWidget {
  const CladogramStrip({
    super.key,
    required this.lineage,
  });

  final List<String> lineage;

  @override
  Widget build(BuildContext context) {
    if (lineage.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          '—',
          style: DinoCardTheme.bodyStyle(fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CLADOGRAM', style: DinoCardTheme.sectionLabelStyle(fontSize: 10)),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _BranchingCladogramPainter(lineage: lineage),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BranchingCladogramPainter extends CustomPainter {
  _BranchingCladogramPainter({required this.lineage});

  final List<String> lineage;

  @override
  void paint(Canvas canvas, Size size) {
    if (lineage.isEmpty) return;

    final linePaint = Paint()
      ..color = DinoCardTheme.cardAccent.withValues(alpha: 0.65)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final nodeCount = lineage.length;
    final rowHeight =
        nodeCount <= 1 ? 0.0 : (size.height - 20) / (nodeCount - 1);

    final positions = <Offset>[];
    for (var i = 0; i < nodeCount; i++) {
      final y = nodeCount <= 1 ? size.height / 2 : 10 + i * rowHeight;
      final x = 10 + (i / _mathMax(nodeCount - 1, 1)) * (size.width * 0.5);
      positions.add(Offset(x, y));
    }

    for (var i = 0; i < positions.length - 1; i++) {
      final start = positions[i];
      final end = positions[i + 1];
      final midX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(midX, start.dy)
        ..lineTo(midX, end.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, linePaint);
    }

    for (var i = 0; i < lineage.length; i++) {
      final isLast = i == lineage.length - 1;
      final pos = positions[i];
      final dotPaint = Paint()
        ..color =
            isLast ? DinoCardTheme.cardTextPrimary : DinoCardTheme.cardAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, isLast ? 5 : 4, dotPaint);

      final fontSize = isLast ? 12.0 : 10.5;
      final textPainter = TextPainter(
        text: TextSpan(
          text: lineage[i].toUpperCase(),
          style: TextStyle(
            color: isLast
                ? DinoCardTheme.cardTextPrimary
                : DinoCardTheme.cardAccent.withValues(alpha: 0.85),
            fontSize: fontSize,
            fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width - pos.dx - 8);

      textPainter.paint(
        canvas,
        Offset(pos.dx + 10, pos.dy - textPainter.height / 2),
      );
    }
  }

  double _mathMax(double a, double b) => a > b ? a : b;

  @override
  bool shouldRepaint(covariant _BranchingCladogramPainter oldDelegate) {
    return oldDelegate.lineage != lineage;
  }
}
