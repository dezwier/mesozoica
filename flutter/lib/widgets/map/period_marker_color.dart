import 'package:flutter/material.dart';

import '../../theme/mesozoica_theme.dart';

const Color _jurassicGray = Color.fromARGB(255, 195, 195, 195);
const Color _triassicOrange = Color.fromARGB(255, 221, 133, 0);

/// Primary marker hue — always the light-theme brown so markers match on dark tiles.
Color mapMarkerPrimaryColor() => MesozoicaTheme.light.colorScheme.primary;

/// Cretaceous keeps the theme brown; Jurassic and Triassic use distinct warm hues.
Color periodMarkerColor(String? period) {
  switch (period?.toLowerCase()) {
    case 'cretaceous':
      return mapMarkerPrimaryColor();
    case 'jurassic':
      return _jurassicGray;
    case 'triassic':
      return _triassicOrange;
    default:
      return mapMarkerPrimaryColor();
  }
}
