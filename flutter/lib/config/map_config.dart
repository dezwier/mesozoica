import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Map tile URLs and zoom constants ported from mesosoica.
class MapConfig {
  MapConfig._();

  static const double initialZoom = 3.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 16.4;
  static const double centerOnMeZoom = 10.0;
  static const double markerDetailZoom = 8.0;

  static const LatLng defaultCenter = LatLng(20.0, 0.0);

  static const double markerSize = 40.0;
  static const double markerIconSize = 22.0;

  static const String esriLight =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
  static const String esriDark =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
  static const String osmNoLabels =
      'https://tiles.wmflabs.org/osm-no-labels/{z}/{x}/{y}.png';

  static const List<String> tileSubdomains = ['a', 'b', 'c', 'd'];
  static const String userAgentPackageName = 'com.mesozoica.app';

  static String tileUrlForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? esriDark : esriLight;
  }

  static double fossilMarkerSize(double zoom, {bool selected = false}) {
    final base = (zoom + 3).clamp(12.0, 22.0);
    return selected ? base + 4 : base;
  }
}
