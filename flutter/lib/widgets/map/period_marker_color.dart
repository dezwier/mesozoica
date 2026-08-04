import 'package:flutter/material.dart';

import '../../config/game_config.dart';

Color _rgb((int, int, int) rgb) => Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3);

PeriodRgbColors get _markers => GameConfig.instance.periodColors.siteMarkers;

/// Primary marker hue — Cretaceous brown from [period_colors.yaml].
Color mapMarkerPrimaryColor() => _rgb(_markers.cretaceous);

/// Period pin color from [period_colors.yaml] `site_markers`.
/// Neutral gray when [period] is null/empty (unidentified excavation site).
Color periodMarkerColor(String? period) {
  final key = period?.trim().toLowerCase();
  if (key == null || key.isEmpty || key == 'unknown') {
    return const Color(0xFF8A867C);
  }
  return _rgb(_markers.forPeriod(key));
}
