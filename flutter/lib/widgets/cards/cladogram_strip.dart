import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';

/// Vertical phylogenetic list with indented dots aligned to taxon names.
class CladogramStrip extends StatelessWidget {
  const CladogramStrip({
    super.key,
    required this.nodes,
  });

  final List<CladogramNode> nodes;

  static const double kRowHeight = 34;
  static const double kIndentStep = 14;
  static const double kRankLineHeight = 10;
  static const double kLabelGap = 2;
  static const double kNameLineHeight = 14;
  static const double kDotSize = 8;
  static const double kDotNameGap = 8;

  static double get _contentBlockHeight =>
      kRankLineHeight + kLabelGap + kNameLineHeight;

  static double get _rowPaddingTop => (kRowHeight - _contentBlockHeight) / 2;

  static double dotYForIndex(int index) =>
      index * kRowHeight +
      _rowPaddingTop +
      kRankLineHeight +
      kLabelGap +
      kNameLineHeight / 2;

  static double dotXForDepth(int depth) => depth * kIndentStep + kDotSize / 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CLADOGRAM', style: DinoCardTheme.sectionLabelStyle(fontSize: 10)),
        const SizedBox(height: 8),
        if (nodes.isEmpty)
          Text('—', style: DinoCardTheme.bodyStyle(fontSize: 13))
        else
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = nodes.length * kRowHeight;

                  return SizedBox(
                    width: constraints.maxWidth,
                    height: height,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(constraints.maxWidth, height),
                          painter: _CladogramConnectorPainter(
                            nodeCount: nodes.length,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < nodes.length; i++)
                              SizedBox(
                                height: kRowHeight,
                                child: _CladogramNodeRow(
                                  node: nodes[i],
                                  isLast: i == nodes.length - 1,
                                  depth: i,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _CladogramNodeRow extends StatelessWidget {
  const _CladogramNodeRow({
    required this.node,
    required this.isLast,
    required this.depth,
  });

  final CladogramNode node;
  final bool isLast;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * CladogramStrip.kIndentStep),
      child: SizedBox(
        height: CladogramStrip.kRowHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: CladogramStrip.kDotSize + CladogramStrip.kDotNameGap,
              ),
              child: Text(
                node.rankLabel,
                style: DinoCardTheme.rankLabelStyle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: CladogramStrip.kLabelGap),
            Row(
              children: [
                Container(
                  width: CladogramStrip.kDotSize,
                  height: CladogramStrip.kDotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLast
                        ? DinoCardTheme.cardTextPrimary
                        : DinoCardTheme.cardAccent.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: CladogramStrip.kDotNameGap),
                Expanded(
                  child: Text(
                    node.name.toUpperCase(),
                    style: TextStyle(
                      color: isLast
                          ? DinoCardTheme.cardTextPrimary
                          : DinoCardTheme.cardAccent.withValues(alpha: 0.85),
                      fontSize: isLast ? 12 : 10.5,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CladogramConnectorPainter extends CustomPainter {
  _CladogramConnectorPainter({required this.nodeCount});

  final int nodeCount;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodeCount <= 1) return;

    final linePaint = Paint()
      ..color = DinoCardTheme.cardAccent.withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < nodeCount - 1; i++) {
      final parentX = CladogramStrip.dotXForDepth(i);
      final parentY = CladogramStrip.dotYForIndex(i);
      final childLeftX =
          CladogramStrip.dotXForDepth(i + 1) - CladogramStrip.kDotSize / 2;
      final childY = CladogramStrip.dotYForIndex(i + 1);

      final path = Path()
        ..moveTo(parentX, parentY)
        ..lineTo(parentX, childY)
        ..lineTo(childLeftX, childY);
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CladogramConnectorPainter oldDelegate) {
    return oldDelegate.nodeCount != nodeCount;
  }
}
