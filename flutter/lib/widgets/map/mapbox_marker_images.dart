import 'dart:ui' as ui;

import '../../config/map_config.dart';

/// Soft shadow disc is slightly larger than the fill so a halo peeks out.
const double mapboxMarkerShadowRadiusScale = 1.22;

/// Mapbox circle-blur for the shadow layer (1 = only centerpoint opaque).
const double mapboxMarkerShadowBlur = 0.7;

/// Shadow fill opacity (black).
const double mapboxMarkerShadowOpacity = 0.34;

/// Selected-marker inner dot radius as a fraction of the fill radius.
const double mapboxMarkerSelectionDotScale = 0.38;

/// Circle radius in px at [zoom].
///
/// Endpoints stay ~4 (zoomed out) and ~8 (zoomed in). Mid zooms stay closer
/// to the small size via a strong ease-in, so markers only grow near max.
double mapboxMarkerRadiusForZoom(double zoom) {
  final t = ((zoom - MapConfig.minZoom) /
          (MapConfig.maxZoom - MapConfig.minZoom))
      .clamp(0.0, 1.0);
  // t^3 keeps mid-range small; t=0 and t=1 unchanged.
  final eased = t * t * t;
  return ui.lerpDouble(4.0, 8.0, eased)!;
}

/// Integer bucket so tiny zoom jitter does not thrash radius updates.
int mapboxMarkerSizeBucket(double zoom) {
  return mapboxMarkerRadiusForZoom(zoom).round();
}

/// Kept for tests / cache key compatibility (circles need no PNG).
String mapboxMarkerImageKey({
  required String? period,
  required int sizeBucket,
}) {
  final periodKey = (period ?? 'default').toLowerCase();
  return '$periodKey|dot|$sizeBucket';
}
