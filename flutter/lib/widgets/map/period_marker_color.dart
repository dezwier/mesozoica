import 'package:flutter/material.dart';

/// Marker fill color by geological period (Cretaceous darkest → Triassic lightest).
Color periodMarkerColor(String? period, ColorScheme scheme) {
  switch (period?.toLowerCase()) {
    case 'cretaceous':
      return scheme.primary;
    case 'jurassic':
      return scheme.secondary;
    case 'triassic':
      return scheme.tertiary;
    default:
      return scheme.primary;
  }
}
