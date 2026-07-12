import 'package:flutter/material.dart';

import '../../config/map_config.dart';

class ZoomSlider extends StatelessWidget {
  const ZoomSlider({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    this.minZoom = MapConfig.minZoom,
    this.maxZoom = MapConfig.maxZoom,
  });

  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final double minZoom;
  final double maxZoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 40,
      height: 150,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: RotatedBox(
          quarterTurns: 3,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor:
                  theme.colorScheme.outline.withValues(alpha: 0.3),
              thumbColor: theme.colorScheme.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 4,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: currentZoom.clamp(minZoom, maxZoom),
              min: minZoom,
              max: maxZoom,
              divisions: ((maxZoom - minZoom) * 20).round(),
              onChanged: onZoomChanged,
            ),
          ),
        ),
      ),
    );
  }
}
