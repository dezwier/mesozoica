import 'package:flutter/material.dart';

import 'zoom_slider.dart';

class MapControlButtons extends StatelessWidget {
  const MapControlButtons({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.onCenterLocation,
    required this.rotateMap,
    required this.onToggleRotation,
    this.filterFab,
  });

  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onCenterLocation;
  final bool rotateMap;
  final VoidCallback onToggleRotation;
  final Widget? filterFab;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'toggle_rotation',
            onPressed: onToggleRotation,
            tooltip: rotateMap
                ? 'Fixed plan: rotate marker with phone'
                : 'Rotating map: keep marker pointing up',
            child: Icon(
              rotateMap ? Icons.navigation_outlined : Icons.explore_outlined,
            ),
          ),
          FloatingActionButton.small(
            heroTag: 'center_location',
            onPressed: onCenterLocation,
            tooltip: 'Center on my location',
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 5),
          ZoomSlider(
            currentZoom: currentZoom,
            onZoomChanged: onZoomChanged,
          ),
          if (filterFab != null) ...[
            const SizedBox(height: 10),
            filterFab!,
          ],
        ],
      ),
    );
  }
}
