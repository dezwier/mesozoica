import 'package:flutter/material.dart';

import '../../config/map_config.dart';

class FossilMarker extends StatelessWidget {
  const FossilMarker({
    super.key,
    required this.size,
    required this.selected,
    required this.showIcon,
    required this.color,
  });

  final double size;
  final bool selected;
  final bool showIcon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final opacity = selected ? 1.0 : 0.75;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
        border: Border.all(
          color: Colors.white.withValues(alpha: opacity),
          width: selected ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2 * opacity),
            blurRadius: selected ? 2 : 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: showIcon
          ? Icon(
              Icons.terrain,
              color: Colors.white.withValues(alpha: opacity),
              size: size * 0.65,
            )
          : null,
    );
  }
}

double fossilMarkerSizeForZoom(double zoom, {bool selected = false}) {
  return MapConfig.fossilMarkerSize(zoom, selected: selected);
}

bool fossilMarkerShowsIcon(double zoom) {
  return zoom >= MapConfig.markerDetailZoom;
}
