import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Expands [bounds] so markers slightly outside the viewport are preloaded.
LatLngBounds paddedVisibleBounds(
  LatLngBounds bounds, {
  double padding = 0.25,
}) {
  final latSpan = bounds.north - bounds.south;
  final lngSpan = bounds.east - bounds.west;
  return LatLngBounds(
    LatLng(
      bounds.south - latSpan * padding,
      bounds.west - lngSpan * padding,
    ),
    LatLng(
      bounds.north + latSpan * padding,
      bounds.east + lngSpan * padding,
    ),
  );
}

/// Clamps WGS84 bounds to ranges accepted by `GET /sites` bbox params.
///
/// Mapbox can report unwrapped longitudes (e.g. −209…216) when zoomed out
/// past one world copy. Returns null for antimeridian-spanning views
/// (`west > east`) which the bbox API does not support.
LatLngBounds? clampBoundsForSitesApi(LatLngBounds bounds) {
  final south = bounds.south.clamp(-90.0, 90.0);
  final north = bounds.north.clamp(-90.0, 90.0);
  if (south > north) return null;

  var west = bounds.west;
  var east = bounds.east;
  if (east - west >= 360.0) {
    west = -180.0;
    east = 180.0;
  } else {
    west = west.clamp(-180.0, 180.0);
    east = east.clamp(-180.0, 180.0);
  }
  if (west > east) return null;
  return LatLngBounds(LatLng(south, west), LatLng(north, east));
}
