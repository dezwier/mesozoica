import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Web stand-in for [MapboxCameraCoordinator]: drives a `flutter_map` camera.
class MapboxCameraCoordinator {
  MapController? _map;
  LatLng? _center;
  double? _zoom;
  double? _viewportWidth;
  double? _viewportHeight;
  bool rotateWithHeading = false;

  final ValueNotifier<int> cameraMotionEpoch = ValueNotifier<int>(0);

  void notifyCameraMotion() {
    cameraMotionEpoch.value++;
  }

  void bindFlutterMap(MapController map) {
    _map = map;
  }

  void detach() {
    _map = null;
  }

  void setViewportHeight(double height) {
    if (height <= 0) return;
    _viewportHeight = height;
  }

  void setViewportSize({required double width, required double height}) {
    if (width <= 0 || height <= 0) return;
    _viewportWidth = width;
    _viewportHeight = height;
  }

  Size? get viewportSize {
    final width = _viewportWidth;
    final height = _viewportHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  Future<LatLng?> coordinateForPixel(Offset pixel) async {
    final map = _map;
    if (map == null) return null;
    try {
      return map.camera.offsetToCrs(pixel);
    } catch (_) {
      return null;
    }
  }

  Future<List<Offset?>> pixelsForCoordinates(List<LatLng> points) async {
    final map = _map;
    if (map == null || points.isEmpty) {
      return List<Offset?>.filled(points.length, null);
    }
    try {
      return [
        for (final point in points)
          map.camera.latLngToScreenPoint(point).toOffset(),
      ];
    } catch (_) {
      return List<Offset?>.filled(points.length, null);
    }
  }

  Future<({double pitch, double bearing})?> currentAttitude() async {
    final map = _map;
    if (map == null) return (pitch: 0.0, bearing: 0.0);
    return (pitch: 0.0, bearing: map.camera.rotation);
  }

  void clearPendingFollow() {}

  Future<LatLngBounds?> visibleBounds() async {
    final map = _map;
    if (map == null) return null;
    try {
      return map.camera.visibleBounds;
    } catch (_) {
      return null;
    }
  }

  Future<void> followLocation(
    LatLng location, {
    required bool followUser,
    double? zoom,
  }) async {
    if (!followUser) return;
    await centerOn(
      location,
      zoom: zoom ?? _zoom ?? _map?.camera.zoom ?? 14,
      headingDeg: 0,
      durationMs: 0,
    );
  }

  Future<void> setZoom(double zoom) async {
    final map = _map;
    _zoom = zoom;
    if (map == null) return;
    map.move(map.camera.center, zoom);
    notifyCameraMotion();
  }

  Future<void> centerOn(
    LatLng location, {
    required double zoom,
    required double headingDeg,
    int durationMs = 500,
  }) async {
    _center = location;
    _zoom = zoom;
    final map = _map;
    if (map == null) return;
    map.move(location, zoom);
    if (rotateWithHeading) {
      map.rotate(headingDeg);
    }
    notifyCameraMotion();
  }

  Future<void> fitRoute(
    List<LatLng> route, {
    int durationMs = 1200,
    double padding = 56,
  }) async {
    if (route.isEmpty) return;
    final map = _map;
    if (map == null) {
      _center = route.first;
      return;
    }
    map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(route),
        padding: EdgeInsets.all(padding),
      ),
    );
    notifyCameraMotion();
  }

  Future<void> fitVerticalSpanKm(
    LatLng center,
    double spanKm, {
    int durationMs = 1200,
  }) async {
    _center = center;
    final map = _map;
    if (map == null || spanKm <= 0) return;
    const distance = Distance();
    final halfM = spanKm * 500;
    final north = distance.offset(center, halfM, 0);
    final south = distance.offset(center, halfM, 180);
    map.fitCamera(
      CameraFit.bounds(bounds: LatLngBounds.fromPoints([north, south])),
    );
    notifyCameraMotion();
  }

  Future<LatLng?> currentCenter() async {
    return _map?.camera.center ?? _center;
  }

  Future<double?> currentZoom() async {
    return _map?.camera.zoom ?? _zoom;
  }
}
