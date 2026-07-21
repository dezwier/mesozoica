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
    this.leadingActions = const [],
    this.bottom = 12,
  });

  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onCenterLocation;
  final bool rotateMap;
  final VoidCallback onToggleRotation;
  final Widget? filterFab;

  /// Extra FABs stacked above the zoom / location controls (e.g. admin).
  final List<Widget> leadingActions;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final fabTheme = Theme.of(context).floatingActionButtonTheme;

    return Positioned(
      right: 12,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...leadingActions,
          if (!rotateMap) ...[
            ZoomSlider(
              currentZoom: currentZoom,
              onZoomChanged: onZoomChanged,
            ),
            const SizedBox(height: 8),
          ],
          if (!rotateMap)
            FloatingActionButton.small(
              heroTag: 'center_location',
              onPressed: onCenterLocation,
              tooltip: 'Center on my location',
              backgroundColor: fabTheme.backgroundColor,
              foregroundColor: fabTheme.foregroundColor,
              child: const Icon(Icons.my_location),
            ),
          FloatingActionButton.small(
            heroTag: 'toggle_rotation',
            onPressed: onToggleRotation,
            tooltip: rotateMap
                ? 'North-fixed map'
                : 'Rotate map with phone orientation',
            backgroundColor: fabTheme.backgroundColor,
            foregroundColor: fabTheme.foregroundColor,
            child: Icon(
              rotateMap ? Icons.explore : Icons.explore_outlined,
            ),
          ),
          ?filterFab,
        ],
      ),
    );
  }
}
