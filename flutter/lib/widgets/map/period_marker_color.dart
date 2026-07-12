import 'package:flutter/material.dart';

/// Cretaceous keeps the theme brown; Jurassic and Triassic use distinct warm hues.
const Color _jurassicOrange = Color(0xFFFF9800);
const Color _triassicGold = Color(0xFFC5944E);

Color periodMarkerColor(String? period, ColorScheme scheme) {
  switch (period?.toLowerCase()) {
    case 'cretaceous':
      return scheme.primary;
    case 'jurassic':
      return const Color.fromARGB(255, 195, 195, 195);

    case 'triassic':
      return const Color.fromARGB(255, 221, 133, 0);
    default:
      return scheme.primary;
  }
}
