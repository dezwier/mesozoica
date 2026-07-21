import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Map tile URLs and zoom constants ported from mesosoica.
class MapConfig {
  MapConfig._();

  static const double initialZoom = 3.0;
  /// How far the map / zoom slider can pull out (world view).
  static const double minZoom = 1.0;
  /// Default zoom for mini maps on card backs (dino fossil world map).
  static const double cardMapZoom = 1.0;
  /// Slightly tighter zoom for a single site location on the site card back.
  static const double siteCardMapZoom = 2.5;
  static const double maxZoom = 18.0;
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

  /// Public Mapbox token (`pk.*`). Prefer `MAPBOX_ACCESS_TOKEN`; also accepts
  /// Mapbox's docs name `ACCESS_TOKEN`.
  static const String _mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );
  static const String _mapboxAccessTokenAlias = String.fromEnvironment(
    'ACCESS_TOKEN',
    defaultValue: '',
  );

  /// Mapbox Standard style (3D buildings when pitched).
  static const String mapboxStyleUri = 'mapbox://styles/mapbox/standard';

  /// Monochrome Standard basemap theme.
  static const String mapboxBasemapTheme = 'monochrome';

  /// Camera pitch in rotate / follow-orientation mode.
  static const double mapboxFollowPitch = 55.0;

  /// Locked zoom while in Mapbox rotate (AR-style) mode.
  static const double mapboxRotateZoom = 18.0;

  /// Where the follow/rotate target sits on screen in rotate mode, as a
  /// fraction of map height from the bottom (mid-x, this fraction up).
  static const double mapboxRotateFocusFromBottom = 1 / 3;

  /// Zoom used when centering on the user in north-fixed mode.
  static const double mapboxFollowZoom = 16.0;

  static String get mapboxAccessToken {
    if (_mapboxAccessToken.isNotEmpty) return _mapboxAccessToken;
    return _mapboxAccessTokenAlias;
  }

  static bool get hasMapboxAccessToken => mapboxAccessToken.isNotEmpty;

  static String tileUrlForBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? cartoDark : cartoLight;
  }

  static double fossilMarkerSize(double zoom, {bool selected = false}) {
    // [selected] kept for call-site compatibility; size no longer grows.
    return (zoom + 3).clamp(12.0, 18.0);
  }
}
