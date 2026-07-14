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
