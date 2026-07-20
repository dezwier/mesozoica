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
    final opacity = selected ? 1.0 : 0.75;
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: opacity),
      border: Border.all(
        color: Colors.white.withValues(alpha: opacity),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2 * opacity),
          blurRadius: selected ? 2 : 1,
          offset: const Offset(0, 1),
        ),
      ],
    );
    final dotSize = size * selectionDotScale;
    final child = Stack(
      alignment: Alignment.center,
      children: [
        if (showIcon)
          Icon(
            Icons.terrain,
            color: Colors.white.withValues(alpha: opacity),
            size: size * 0.65,
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
    );

    if (!animateSelection) {
      return Container(
        width: size,
        height: size,
        decoration: decoration,
        child: child,
      );
    }

    return AnimatedContainer(
      duration: selectionDuration,
      curve: selectionCurve,
      width: size,
      height: size,
      decoration: decoration,
      child: child,
    );
  }
}

double fossilMarkerSizeForZoom(double zoom, {bool selected = false}) {
  return MapConfig.fossilMarkerSize(zoom, selected: selected);
}

bool fossilMarkerShowsIcon(double zoom) {
  return zoom >= MapConfig.markerDetailZoom;
}
