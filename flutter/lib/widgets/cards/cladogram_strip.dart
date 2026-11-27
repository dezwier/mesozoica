import 'package:flutter/material.dart';

import '../../models/dinosaur.dart';
import '../../theme/dino_card_theme.dart';
import '../../utils/display_text.dart';

class _CladogramLayout {
  const _CladogramLayout({required this.scale, required this.rowHeight});

  final double scale;
  final double rowHeight;

  double get rankLineHeight => 9 * scale;
  double get labelGap => 1 * scale;
  double get nameLineHeight => 13 * scale;
  double get dotSize => 6.5 * scale;
  double get dotNameGap => 8 * scale;

  double get contentBlockHeight => rankLineHeight + labelGap + nameLineHeight;

  double get rowPaddingTop => (rowHeight - contentBlockHeight) / 2;

  double get dotSlot => dotSize + 2;

  double get dotX => dotSlot / 2;

  double dotYForIndex(int index) =>
      index * rowHeight +
      rowPaddingTop +
      rankLineHeight +
      labelGap +
      nameLineHeight / 2;
}

/// Vertical phylogenetic list with dots connected by straight vertical lines.
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
                lineColor: cardTheme.cardAccent.withValues(alpha: 0.9),
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

    const naturalRow = 28.0;
    final fittedScale = scale.clamp(0.72, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        var rowHeight = naturalRow * fittedScale;
        final bounded =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0;
        if (bounded) {
          rowHeight = constraints.maxHeight / nodes.length;
          if (rowHeight < 22) rowHeight = 22;
        }
        final layout = _CladogramLayout(
          scale: fittedScale,
          rowHeight: rowHeight,
        );
        final width = !centered && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : null;
        return _buildTree(cardTheme: cardTheme, layout: layout, width: width);
      },
    );
  }
}

TextStyle _nodeStyle(DinoCardTheme cardTheme, bool isLast, double scale) {
  final color = cardTheme.isLight
      ? cardTheme.museumTileInk
      : (isLast ? const Color(0xFFF0D7A4) : const Color(0xFFE6D3BE));
  return TextStyle(
    fontFamily: DinoCardTheme.titleFontFamily,
    color: color,
    fontSize: (isLast ? 12.5 : 11) * scale,
    fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.05,
  );
}

class _CladogramNodeRow extends StatelessWidget {
  const _CladogramNodeRow({
    required this.node,
    required this.isLast,
    required this.cardTheme,
    required this.layout,
    required this.centered,
  });

  final CladogramNode node;
  final bool isLast;
  final DinoCardTheme cardTheme;
  final _CladogramLayout layout;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: layout.rowHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: layout.dotSlot + layout.dotNameGap),
            child: Text(
              node.rankLabel,
              style: cardTheme
                  .rankLabelStyle(fontSize: 7 * layout.scale)
                  .copyWith(
                    fontFamily: DinoCardTheme.titleFontFamily,
                    color: cardTheme.cardAccent.withValues(alpha: 0.92),
                    letterSpacing: 1.15,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: layout.labelGap),
          Row(
            mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
            children: [
              SizedBox(
                width: layout.dotSlot,
                height: layout.dotSlot,
                child: Center(
                  child: Container(
                    width: isLast ? layout.dotSize + 1.4 : layout.dotSize,
                    height: isLast ? layout.dotSize + 1.4 : layout.dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isLast
                          ? const Color(0xFFF6E2A8)
                          : cardTheme.cardAccent,
                      boxShadow: [
                        BoxShadow(
                          color: cardTheme.cardAccent.withValues(
                            alpha: isLast ? 0.7 : 0.35,
                          ),
                          blurRadius: isLast ? 6 : 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: layout.dotNameGap),
              if (centered)
                Text(
                  capitalizeLeadingLetter(node.name),
                  style: _nodeStyle(cardTheme, isLast, layout.scale),
                  maxLines: 1,
                  softWrap: false,
                )
              else
                Expanded(
                  child: Text(
                    capitalizeLeadingLetter(node.name),
                    style: _nodeStyle(cardTheme, isLast, layout.scale),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
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

    final glow = Paint()
      ..color = lineColor.withValues(alpha: 0.28)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < nodeCount - 1; i++) {
      final x = layout.dotX;
      final parentY = layout.dotYForIndex(i);
      final childY = layout.dotYForIndex(i + 1);

      canvas.drawLine(Offset(x, parentY), Offset(x, childY), glow);
      canvas.drawLine(Offset(x, parentY), Offset(x, childY), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CladogramConnectorPainter oldDelegate) {
    return oldDelegate.nodeCount != nodeCount ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.layout.scale != layout.scale;
  }
}
