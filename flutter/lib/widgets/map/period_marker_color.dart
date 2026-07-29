import 'package:flutter/material.dart';

import '../../config/game_config.dart';

Color _rgb((int, int, int) rgb) => Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3);

PeriodRgbColors get _markers => GameConfig.instance.periodColors.siteMarkers;

/// Primary marker hue — Cretaceous brown from [period_colors.yaml].
Color mapMarkerPrimaryColor() => _rgb(_markers.cretaceous);

/// Period pin color from [period_colors.yaml] `site_markers`.
Color periodMarkerColor(String? period) {
  return _rgb(_markers.forPeriod(period ?? 'cretaceous'));
}
