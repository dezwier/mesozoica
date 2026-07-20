import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Map tile URLs and zoom constants ported from mesosoica.
class MapConfig {
  MapConfig._();

  static const double initialZoom = 3.0;
  static const double minZoom = 2.0;
  /// Default zoom for mini maps on card backs (dino fossil world map).
  static const double cardMapZoom = 1.0;
  /// Slightly tighter zoom for a single site location on the site card back.
  static const double siteCardMapZoom = 2.5;
  static const double maxZoom = 16.4;
  static const double centerOnMeZoom = 10.0;
  static const double markerDetailZoom = 8.0;

  static const LatLng defaultCenter = LatLng(20.0, 0.0);

  static const double markerSize = 40.0;
  static const double markerIconSize = 22.0;

  static const String cartoLight =
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
  static const String cartoDark =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  static const List<String> tileSubdomains = ['a', 'b', 'c', 'd'];
  static const String userAgentPackageName = 'com.mesozoica.app';

  static String tileUrlForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? cartoDark : cartoLight;
  }

  static double fossilMarkerSize(double zoom, {bool selected = false}) {
    final base = (zoom + 3).clamp(12.0, 22.0);
    return selected ? base * 2 : base;
  }
}
