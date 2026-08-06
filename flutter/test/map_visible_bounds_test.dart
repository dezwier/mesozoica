import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesozoica/utils/map_visible_bounds.dart';

void main() {
  test('clampBoundsForSitesApi returns null for full-world unwrapped span', () {
    final raw = LatLngBounds(
      const LatLng(-37.45, -209.10),
      const LatLng(66.48, 216.47),
    );
    expect(clampBoundsForSitesApi(raw), isNull);
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

  test('clampBoundsForSitesApi returns null when east-west span >= 360', () {
    final raw = LatLngBounds(
      const LatLng(-10.0, -200.0),
      const LatLng(10.0, 200.0),
    );
    expect(clampBoundsForSitesApi(raw), isNull);
  });

  test('clampBoundsForSitesApi clamps moderate unwrapped longitudes', () {
    final raw = LatLngBounds(
      const LatLng(50.0, -185.0),
      const LatLng(51.0, -175.0),
    );
    final safe = clampBoundsForSitesApi(raw)!;
    expect(safe.west, -180.0);
    expect(safe.east, -175.0);
  });

  test('padded then clamped stays within API range for narrow view', () {
    final view = LatLngBounds(
      const LatLng(50.0, 3.0),
      const LatLng(50.05, 3.05),
    );
    final safe = clampBoundsForSitesApi(paddedVisibleBounds(view))!;
    expect(safe.west, greaterThanOrEqualTo(-180.0));
    expect(safe.east, lessThanOrEqualTo(180.0));
    expect(safe.south, greaterThanOrEqualTo(-90.0));
    expect(safe.north, lessThanOrEqualTo(90.0));
  });

  test('showAllFetchBounds pads the viewport', () {
    final view = LatLngBounds(
      const LatLng(51.0, 4.0),
      const LatLng(51.05, 4.05),
    );
    final fetch = showAllFetchBounds(visibleBounds: view)!;
    expect(fetch.south, lessThan(51.0));
    expect(fetch.north, greaterThan(51.05));
  });

  test('showAllFetchBounds returns null for huge / world viewport', () {
    final view = LatLngBounds(
      const LatLng(-40.0, -100.0),
      const LatLng(60.0, 100.0),
    );
    // Span is fine for clamp — only world-sized / antimeridian fail.
    expect(showAllFetchBounds(visibleBounds: view), isNotNull);

    final world = LatLngBounds(
      const LatLng(-80.0, -200.0),
      const LatLng(80.0, 200.0),
    );
    expect(showAllFetchBounds(visibleBounds: world), isNull);
  });

  test('showAllFetchBounds returns null when visibleBounds is null', () {
    expect(showAllFetchBounds(visibleBounds: null), isNull);
  });
}
