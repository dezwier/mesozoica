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

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentHeight = nodes.length * layout.rowHeight;
        final maxHeight = constraints.maxHeight;
        final maxWidth = constraints.maxWidth;
        final needsScroll =
            maxHeight.isFinite && contentHeight > maxHeight + 0.5;

        final tree = _buildTree(
          cardTheme: cardTheme,
          layout: layout,
          width: centered ? null : maxWidth,
        );

        if (needsScroll) {
          return _CladogramScrollFade(
            height: maxHeight,
            fadeColor: cardTheme.cardBackground,
            centered: centered,
            width: centered ? null : maxWidth,
            child: tree,
          );
        }

        return Align(
          alignment: centered ? Alignment.topCenter : Alignment.topLeft,
          child: centered
              ? IntrinsicWidth(child: tree)
              : SizedBox(width: maxWidth, child: tree),
        );
      },
    );
  }
}

const _cladogramScrollFadeHeight = 12.0;

class _CladogramScrollFade extends StatefulWidget {
  const _CladogramScrollFade({
    required this.height,
    required this.fadeColor,
    required this.centered,
    required this.child,
    this.width,
  });

  final double height;
  final Color fadeColor;
  final bool centered;
  final double? width;
  final Widget child;

  @override
  State<_CladogramScrollFade> createState() => _CladogramScrollFadeState();
}

class _CladogramScrollFadeState extends State<_CladogramScrollFade> {
  final ScrollController _controller = ScrollController();
  bool _showTopFade = false;
  bool _showBottomFade = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void didUpdateWidget(covariant _CladogramScrollFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFades());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateFades);
    _controller.dispose();
    super.dispose();
  }

  void _updateFades() {
    if (!_controller.hasClients) return;

    final position = _controller.position;
    final showTop = position.pixels > 0.5;
    final showBottom = position.pixels < position.maxScrollExtent - 0.5;

    if (showTop == _showTopFade && showBottom == _showBottomFade) return;

    setState(() {
      _showTopFade = showTop;
      _showBottomFade = showBottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget scrollChild = widget.child;
    if (widget.centered) {
      scrollChild = Align(
        alignment: Alignment.topCenter,
        child: IntrinsicWidth(child: widget.child),
      );
    } else if (widget.width != null) {
      scrollChild = SizedBox(width: widget.width, child: widget.child);
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SingleChildScrollView(
            controller: _controller,
            physics: const ClampingScrollPhysics(),
            child: scrollChild,
          ),
          if (_showTopFade)
            _CladogramScrollFadeOverlay(
              fadeColor: widget.fadeColor,
              atTop: true,
            ),
          if (_showBottomFade)
            _CladogramScrollFadeOverlay(
              fadeColor: widget.fadeColor,
              atTop: false,
            ),
        ],
      ),
    );
  }
}

class _CladogramScrollFadeOverlay extends StatelessWidget {
  const _CladogramScrollFadeOverlay({
    required this.fadeColor,
    required this.atTop,
  });

  final Color fadeColor;
  final bool atTop;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: atTop ? 0 : null,
      bottom: atTop ? null : 0,
      left: 0,
      right: 0,
      height: _cladogramScrollFadeHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                fadeColor,
                fadeColor.withValues(alpha: 0),
              ],
            ),
          ),
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
