import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import '../../theme/map_chrome_theme.dart';

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
    return Container(
      width: 40,
      height: 150,
      decoration: BoxDecoration(
        color: MapChromeTheme.darkGlassSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
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
              activeTrackColor: MapChromeTheme.cream,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
              thumbColor: MapChromeTheme.cream,
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
