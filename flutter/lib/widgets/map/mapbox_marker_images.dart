import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config/map_config.dart';

/// Soft shadow disc is slightly larger than the fill so a halo peeks out.
const double mapboxMarkerShadowRadiusScale = 1.34;

/// Dark cylinder rim under the fill (gives the puck height).
const double mapboxMarkerRimRadiusScale = 1.12;

/// Soft specular highlight on the puck top.
const double mapboxMarkerHighlightRadiusScale = 0.52;

/// Mapbox circle-blur for the shadow layer (1 = only centerpoint opaque).
const double mapboxMarkerShadowBlur = 0.78;

/// Soft blur on the highlight so it reads as a specular glint.
const double mapboxMarkerHighlightBlur = 0.42;

/// Shadow fill opacity (black).
const double mapboxMarkerShadowOpacity = 0.40;

/// Rim fill opacity (darkened period color).
const double mapboxMarkerRimOpacity = 0.92;

/// Highlight fill opacity (lightened period color).
const double mapboxMarkerHighlightOpacity = 0.55;

/// Selected-marker inner dot radius as a fraction of the fill radius.
const double mapboxMarkerSelectionDotScale = 0.38;

/// Circle radius in px at [zoom].
///
/// Endpoints stay ~4 (zoomed out) and ~8 (zoomed in). Mid zooms stay closer
/// to the small size via a strong ease-in, so markers only grow near max.
double mapboxMarkerRadiusForZoom(double zoom) {
  final t =
      ((zoom - MapConfig.minZoom) / (MapConfig.maxZoom - MapConfig.minZoom))
          .clamp(0.0, 1.0);
  // t^3 keeps mid-range small; t=0 and t=1 unchanged.
  final eased = t * t * t;
  return ui.lerpDouble(4.0, 8.0, eased)!;
}

/// Integer bucket so tiny zoom jitter does not thrash radius updates.
int mapboxMarkerSizeBucket(double zoom) {
  return mapboxMarkerRadiusForZoom(zoom).round();
}

/// Darker shade for the puck's cylinder rim / underside.
Color mapboxMarkerRimColor(Color fill) {
  return Color.lerp(fill, const Color(0xFF1A120E), 0.42)!;
}

/// Lighter shade for the puck's top specular highlight.
Color mapboxMarkerHighlightColor(Color fill) {
  return Color.lerp(fill, Colors.white, 0.55)!;
}

/// Kept for tests / cache key compatibility (circles need no PNG).
String mapboxMarkerImageKey({
  required String? period,
  required int sizeBucket,
}) {
  final periodKey = (period ?? 'default').toLowerCase();
  return '$periodKey|dot|$sizeBucket';
}
