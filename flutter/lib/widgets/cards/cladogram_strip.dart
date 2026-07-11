import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';

class _CladogramLayout {
  const _CladogramLayout({required this.scale});

  final double scale;

  double get rowHeight => 34 * scale;
  double get indentStep => 14 * scale;
  double get rankLineHeight => 10 * scale;
  double get labelGap => 2 * scale;
  double get nameLineHeight => 14 * scale;
  double get dotSize => 8 * scale;
  double get dotNameGap => 8 * scale;

  double get contentBlockHeight =>
      rankLineHeight + labelGap + nameLineHeight;

  double get rowPaddingTop => (rowHeight - contentBlockHeight) / 2;

  double dotYForIndex(int index) =>
      index * rowHeight +
      rowPaddingTop +
      rankLineHeight +
      labelGap +
      nameLineHeight / 2;

  double dotXForDepth(int depth) => depth * indentStep + dotSize / 2;
}

/// Vertical phylogenetic list with indented dots aligned to taxon names.
class CladogramStrip extends StatelessWidget {
  const CladogramStrip({
    super.key,
    required this.nodes,
    this.scale = 1.0,
    this.centered = true,
  });

  final List<CladogramNode> nodes;
  final double scale;
  final bool centered;

  Widget _buildTree({
    required DinoCardTheme cardTheme,
    required _CladogramLayout layout,
    required double? width,
  }) {
    final height = nodes.length * layout.rowHeight;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CladogramConnectorPainter(
                layout: layout,
                nodeCount: nodes.length,
                lineColor: cardTheme.cardAccent.withValues(alpha: 0.18),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < nodes.length; i++)
                SizedBox(
                  height: layout.rowHeight,
                  child: _CladogramNodeRow(
                    node: nodes[i],
                    isLast: i == nodes.length - 1,
                    depth: i,
                    cardTheme: cardTheme,
                    layout: layout,
                    centered: centered,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final layout = _CladogramLayout(scale: scale);

    if (nodes.isEmpty) {
      return Align(
        alignment: centered ? Alignment.topCenter : Alignment.topLeft,
        child: Text(
          '—',
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: cardTheme.bodyStyle(fontSize: 13 * scale),
        ),
      );
    }

    if (!centered) {
      return Align(
        alignment: Alignment.topLeft,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return _buildTree(
              cardTheme: cardTheme,
              layout: layout,
              width: constraints.maxWidth,
            );
          },
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: IntrinsicWidth(
        child: _buildTree(
          cardTheme: cardTheme,
          layout: layout,
          width: null,
        ),
      ),
    );
  }
}

class _CladogramNodeRow extends StatelessWidget {
  const _CladogramNodeRow({
    required this.node,
    required this.isLast,
    required this.depth,
    required this.cardTheme,
    required this.layout,
    required this.centered,
  });

  final CladogramNode node;
  final bool isLast;
  final int depth;
  final DinoCardTheme cardTheme;
  final _CladogramLayout layout;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * layout.indentStep),
      child: SizedBox(
        height: layout.rowHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: layout.dotSize + layout.dotNameGap,
              ),
              child: Text(
                node.rankLabel,
                style: cardTheme.rankLabelStyle(fontSize: 8 * layout.scale),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: layout.labelGap),
            Row(
              mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Container(
                  width: layout.dotSize,
                  height: layout.dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLast
                        ? cardTheme.cardTextPrimary
                        : cardTheme.cardAccent.withValues(alpha: 0.7),
                  ),
                ),
                SizedBox(width: layout.dotNameGap),
                if (centered)
                  Text(
                    node.name.toUpperCase(),
                    style: TextStyle(
                      color: cardTheme.cladogramNodeColor(isLast: isLast),
                      fontSize: (isLast ? 12 : 10.5) * layout.scale,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    softWrap: false,
                  )
                else
                  Expanded(
                    child: Text(
                      node.name.toUpperCase(),
                      style: TextStyle(
                        color: cardTheme.cladogramNodeColor(isLast: isLast),
                        fontSize: (isLast ? 12 : 10.5) * layout.scale,
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
  _CladogramConnectorPainter({
    required this.layout,
    required this.nodeCount,
    required this.lineColor,
  });

  final _CladogramLayout layout;
  final int nodeCount;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodeCount <= 1) return;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < nodeCount - 1; i++) {
      final parentX = layout.dotXForDepth(i);
      final parentY = layout.dotYForIndex(i);
      final childLeftX =
          layout.dotXForDepth(i + 1) - layout.dotSize / 2;
      final childY = layout.dotYForIndex(i + 1);

      final path = Path()
        ..moveTo(parentX, parentY)
        ..lineTo(parentX, childY)
        ..lineTo(childLeftX, childY);
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CladogramConnectorPainter oldDelegate) {
    return oldDelegate.nodeCount != nodeCount ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.layout.scale != layout.scale;
  }
}
