import 'package:flutter/material.dart';

import '../../config/map_config.dart';

class FossilMarker extends StatelessWidget {
  const FossilMarker({
    super.key,
    required this.size,
    required this.selected,
    required this.showIcon,
    required this.color,
    this.animateSelection = false,
  });

  final double size;
  final bool selected;
  final bool showIcon;
  final Color color;

  /// When true, opacity/border ease with selection.
  final bool animateSelection;

  static const selectionDuration = Duration(milliseconds: 250);
  static const selectionCurve = Curves.easeOutCubic;

  /// Inner selection-dot diameter as a fraction of [size].
  static const selectionDotScale = 0.38;

  @override
  Widget build(BuildContext context) {
    final opacity = selected ? 1.0 : 0.85;
    final rimColor = Color.lerp(
      color,
      const Color(0xFF1A120E),
      0.42,
    )!.withValues(alpha: opacity);
    final fillColor = color.withValues(alpha: opacity);
    final highlightColor = Color.lerp(
      color,
      Colors.white,
      0.55,
    )!.withValues(alpha: 0.55 * opacity);
    // Keep the outer footprint at [size]; rim/fill/highlight scale inward.
    final fillSize = size / 1.12;
    final highlightSize = fillSize * 0.52;
    final dotSize = fillSize * selectionDotScale;

    final puck = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft ground shadow (may extend slightly outside the box).
          Container(
            width: fillSize,
            height: fillSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32 * opacity),
                  blurRadius: selected ? 3.5 : 2.5,
                  spreadRadius: 0.2,
                  offset: const Offset(0, 1.2),
                ),
              ],
            ),
          ),
          // Dark cylinder rim.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: rimColor),
          ),
          // Period fill with white bevel.
          Container(
            width: fillSize,
            height: fillSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fillColor,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.92 * opacity),
                width: 1.2,
              ),
            ),
          ),
          // Specular highlight.
          Align(
            alignment: const Alignment(-0.15, -0.2),
            child: Container(
              width: highlightSize,
              height: highlightSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [highlightColor, highlightColor.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          if (showIcon)
            Icon(
              Icons.terrain,
              color: Colors.white.withValues(alpha: opacity),
              size: fillSize * 0.65,
            ),
          if (selected)
            Container(
              width: dotSize,
              height: dotSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );

    if (!animateSelection) return puck;

    return AnimatedScale(
      duration: selectionDuration,
      curve: selectionCurve,
      scale: selected ? 1.06 : 1.0,
      child: puck,
    );
  }
}

double fossilMarkerSizeForZoom(double zoom, {bool selected = false}) {
  return MapConfig.fossilMarkerSize(zoom, selected: selected);
}

bool fossilMarkerShowsIcon(double zoom) {
  return zoom >= MapConfig.markerDetailZoom;
}
