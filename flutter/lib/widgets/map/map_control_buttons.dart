import 'package:flutter/material.dart';

import '../common/chrome_fab.dart';
import 'zoom_slider.dart';

/// Combined center / orientation FAB cycle:
/// 1. North-fixed, not following → center on user
/// 2. North-fixed, following → enter rotate mode
/// 3. Rotate mode → north-fixed, following
enum MapLocationFabMode {
  center,
  enterRotate,
  exitRotate,
}

class MapControlButtons extends StatelessWidget {
  const MapControlButtons({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.locationFabMode,
    required this.onLocationFabPressed,
    this.filterFab,
    this.leadingActions = const [],
    this.bottom = 12,
  });

  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final MapLocationFabMode locationFabMode;
  final VoidCallback onLocationFabPressed;
  final Widget? filterFab;

  /// Extra FABs stacked above the zoom / location controls (e.g. admin).
  final List<Widget> leadingActions;
  final double bottom;

  bool get _rotateMap => locationFabMode == MapLocationFabMode.exitRotate;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String tooltip) = switch (locationFabMode) {
      MapLocationFabMode.center => (
          Icons.my_location,
          'Center on my location',
        ),
      MapLocationFabMode.enterRotate => (
          Icons.explore_outlined,
          'Rotate map with phone orientation',
        ),
      MapLocationFabMode.exitRotate => (
          Icons.explore,
          'North-fixed map',
        ),
    };

    return Positioned(
      right: 12,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...leadingActions,
          if (!_rotateMap) ...[
            ZoomSlider(
              currentZoom: currentZoom,
              onZoomChanged: onZoomChanged,
            ),
            const SizedBox(height: 8),
          ],
          ChromeFab(
            heroTag: 'map_location_mode',
            onPressed: onLocationFabPressed,
            tooltip: tooltip,
            tone: ChromeFabTone.warm,
            child: Icon(icon),
          ),
          ?filterFab,
        ],
      ),
    );
  }
}
