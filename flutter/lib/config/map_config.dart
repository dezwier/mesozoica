import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Mapbox Standard `basemap.theme` color presets (excludes `custom` / LUT).
enum MapboxBasemapTheme {
  standard('default', 'Default'),
  faded('faded', 'Faded'),
  monochrome('monochrome', 'Monochrome');

  const MapboxBasemapTheme(this.value, this.label);

  /// Value passed to Mapbox style import config.
  final String value;
  final String label;

  static MapboxBasemapTheme fromStored(String? stored) {
    for (final theme in values) {
      if (theme.value == stored || theme.name == stored) return theme;
    }
    return MapConfig.mapboxBasemapTheme;
  }
}

/// Map tile URLs and zoom constants ported from mesosoica.
class MapConfig {
  MapConfig._();

  static const double initialZoom = 3.0;
  /// How far the map / zoom slider can pull out (world view).
  static const double minZoom = 2.0;
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

  /// Default Mapbox Standard basemap color theme when none is saved.
  static const MapboxBasemapTheme mapboxBasemapTheme =
      MapboxBasemapTheme.monochrome;

  /// Camera pitch in rotate / follow-orientation mode.
  static const double mapboxFollowPitch = 55.0;

  /// Locked zoom while in Mapbox rotate (AR-style) mode.
  static const double mapboxRotateZoom = 18.0;

  /// Diameter of site photo pins (fixed; no distance scaling).
  static const double rotateMiniCardWidth = 52.0;

  /// Distance (m) within which mini-cards use [rotateMiniCardWidth].
  static const double rotateMiniCardFullSizeWithinM = 55.0;

  /// From this distance (m) onward, cards are half of [rotateMiniCardWidth].
  static const double rotateMiniCardHalfSizeAtM = 200.0;

  /// Card width factor at and beyond [rotateMiniCardHalfSizeAtM] (0.5 = half size).
  static const double rotateMiniCardHalfSizeFactor = 0.5;

  /// Smallest width at the outer cull radius (beyond half-size range).
  static const double rotateMiniCardMinWidth = 28.0;

  /// Corner radius for rotate-mode mini-cards (smaller than full turnables).
  static const double rotateMiniCardBorderRadius = 6.0;

  /// Max mini-cards / pins visible at once (nearest first).
  static const int rotateMaxVisibleCards = 20;

  /// Drop sites farther than this from the camera before pixel projection.
  static const double rotateCardCullRadiusM = 1500.0;

  /// Zoom at/above which north-fixed mode shows photo pins instead of dots.
  static const double sitePinDetailZoom = 16.0;

  /// Expand the viewport bounds used to keep mini-cards (fraction of span).
  static const double rotateViewportPadding = 0.18;

  /// Where the follow/rotate target sits on screen in rotate mode, as a
  /// fraction of map height from the bottom (mid-x, this fraction up).
  static const double mapboxRotateFocusFromBottom = 1 / 3;

  /// Zoom used when centering on the user in north-fixed mode.
  static const double mapboxFollowZoom = 17.0;

  /// Initial zoom when linking to an aerial recon scout (more pulled out than
  /// [mapboxFollowZoom] so the route context is visible). Continuous follow
  /// preserves whatever zoom the user picks afterward.
  static const double mapboxAerialMissionZoom = 14.0;

  /// Camera fly-in duration when focusing an aerial recon mission.
  static const int mapboxAerialMissionFocusDurationMs = 450;

  /// Admin on-demand "sites in view" refuses to paint when the viewport
  /// bbox contains more than this many field sites.
  static const int showAllMaxSites = 1000;

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
