import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/widgets/map/map_visible_bounds.dart';

void main() {
  test('clampBoundsForSitesApi clamps unwrapped Mapbox longitudes', () {
    final raw = LatLngBounds(
      const LatLng(-37.45, -209.10),
      const LatLng(66.48, 216.47),
    );
    final safe = clampBoundsForSitesApi(raw);
    expect(safe, isNotNull);
    expect(safe!.west, -180.0);
    expect(safe.east, 180.0);
    expect(safe.south, -37.45);
    expect(safe.north, 66.48);
  });

  test('clampBoundsForSitesApi clamps padded overshoot past poles', () {
    final raw = LatLngBounds(
      const LatLng(-100.0, -10.0),
      const LatLng(100.0, 10.0),
    );
    final safe = clampBoundsForSitesApi(raw)!;
    expect(safe.south, -90.0);
    expect(safe.north, 90.0);
    expect(safe.west, -10.0);
    expect(safe.east, 10.0);
  });

  test('clampBoundsForSitesApi collapses full-world unwrapped span', () {
    final raw = LatLngBounds(
      const LatLng(-10.0, -200.0),
      const LatLng(10.0, 200.0),
    );
    final safe = clampBoundsForSitesApi(raw)!;
    expect(safe.west, -180.0);
    expect(safe.east, 180.0);
  });

  test('padded then clamped stays within API range', () {
    final view = LatLngBounds(
      const LatLng(-37.45, -170.0),
      const LatLng(66.48, 170.0),
    );
    final safe = clampBoundsForSitesApi(paddedVisibleBounds(view))!;
    expect(safe.west, greaterThanOrEqualTo(-180.0));
    expect(safe.east, lessThanOrEqualTo(180.0));
    expect(safe.south, greaterThanOrEqualTo(-90.0));
    expect(safe.north, lessThanOrEqualTo(90.0));
  });
}
