import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import 'mapbox_site_annotations.dart';

/// Drives Mapbox camera for north-fixed (flat) mode and one-shot transitions.
///
/// Rotate / AR mode uses Mapbox [FollowPuckViewportState] (native heading +
/// location tracking). Do not call [applyHeading] / [followLocation] while
/// FollowPuck owns the camera — Dart [setCamera] fights the native viewport.
///
/// North-fixed GPS follow updates coalesce to the latest value so the camera
/// stays responsive instead of dropping frames while a previous [setCamera]
/// is in flight.
class MapboxCameraCoordinator {
  MapboxMap? _map;
  double _lastHeadingDeg = 0;
  LatLng? _lastFollowedLocation;
  bool _followInFlight = false;
  LatLng? _pendingFollowLocation;
  double? _pendingFollowZoom;
  double? _viewportHeight;
  bool rotateWithHeading = false;

  void attach(MapboxMap map) {
    _map = map;
  }

  void detach() {
    _map = null;
    _lastFollowedLocation = null;
    _pendingFollowLocation = null;
    _pendingFollowZoom = null;
  }

  /// Logical map height from Flutter layout (preferred over [MapboxMap.getSize]).
  void setViewportHeight(double height) {
    if (height <= 0) return;
    _viewportHeight = height;
  }

  /// Drop queued GPS follow so a programmatic [centerOn] is not overwritten.
  void clearPendingFollow() {
    _pendingFollowLocation = null;
    _pendingFollowZoom = null;
  }

  double get _pitch =>
      mapboxPitchForMode(rotateWithHeading: rotateWithHeading);

  double _bearingForMode(double headingDeg) {
    if (!rotateWithHeading) return 0;
    return mapboxBearingFromHeading(headingDeg);
  }

  /// Rotate mode: mid-x, [MapConfig.mapboxRotateFocusFromBottom] from bottom.
  /// North-fixed: true screen center (zero padding).
  MbxEdgeInsets _paddingForMode() {
    if (!rotateWithHeading) {
      return MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0);
    }
    final height = _viewportHeight;
    if (height == null || height <= 0) {
      return MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0);
    }
    // Focus at fraction F from bottom ⇒ y = (1−F)·H from top.
    // With top padding T and bottom 0: center y = (H+T)/2 = (1−F)·H
    // ⇒ T = (1−2F)·H. For F = 1/3: T = H/3.
    final focusFromBottom = MapConfig.mapboxRotateFocusFromBottom;
    final top = height * (1 - 2 * focusFromBottom);
    return MbxEdgeInsets(
      top: top.clamp(0, height),
      left: 0,
      bottom: 0,
      right: 0,
    );
  }

  Future<void> seedCamera({
    required LatLng center,
    required double zoom,
    required double headingDeg,
  }) async {
    final map = _map;
    if (map == null) return;
    _lastHeadingDeg = headingDeg;
    _lastFollowedLocation = center;
    await map.setCamera(
      CameraOptions(
        center: Point(coordinates: Position(center.longitude, center.latitude)),
        zoom: clampMapboxZoom(zoom),
        bearing: _bearingForMode(headingDeg),
        pitch: _pitch,
        padding: _paddingForMode(),
      ),
    );
  }

  /// Switch between north-fixed and heading-follow without remounting.
  ///
  /// Entering rotate mode is a no-op here — [FollowPuckViewportState] owns
  /// pitch/bearing/zoom. Exiting resets to a flat, north-up camera.
  Future<void> applyOrientationMode({
    required bool rotateWithHeading,
    required double headingDeg,
    double? zoom,
  }) async {
    this.rotateWithHeading = rotateWithHeading;
    _lastHeadingDeg = headingDeg;
    if (rotateWithHeading) return;
    final map = _map;
    if (map == null) return;
    await map.setCamera(
      CameraOptions(
        bearing: 0,
        pitch: 0,
        zoom: zoom != null ? clampMapboxZoom(zoom) : null,
        padding: _paddingForMode(),
      ),
    );
  }

  /// No-op: rotate mode uses FollowPuck; north-fixed keeps bearing at 0.
  Future<void> applyHeading(double headingDeg, {bool force = false}) async {}

  /// North-fixed GPS follow only. Rotate mode is owned by FollowPuck.
  Future<void> followLocation(
    LatLng location, {
    required bool followUser,
    double? zoom,
  }) async {
    if (!followUser || rotateWithHeading) return;
    _pendingFollowLocation = location;
    _pendingFollowZoom = zoom;
    if (_followInFlight) return;
    _followInFlight = true;
    try {
      while (_pendingFollowLocation != null) {
        final map = _map;
        if (map == null) return;
        final next = _pendingFollowLocation!;
        final nextZoom = _pendingFollowZoom;
        _pendingFollowLocation = null;
        _pendingFollowZoom = null;
        final previous = _lastFollowedLocation;
        if (previous != null &&
            previous.latitude == next.latitude &&
            previous.longitude == next.longitude) {
          continue;
        }
        _lastFollowedLocation = next;
        await map.setCamera(
          CameraOptions(
            center: Point(
              coordinates: Position(next.longitude, next.latitude),
            ),
            zoom: nextZoom != null ? clampMapboxZoom(nextZoom) : null,
            pitch: _pitch,
            bearing: _bearingForMode(_lastHeadingDeg),
            padding: _paddingForMode(),
          ),
        );
      }
    } finally {
      _followInFlight = false;
    }
  }

  Future<void> setZoom(double zoom) async {
    final map = _map;
    if (map == null) return;
    await map.setCamera(CameraOptions(zoom: clampMapboxZoom(zoom)));
  }

  Future<void> centerOn(
    LatLng location, {
    required double zoom,
    required double headingDeg,
    int durationMs = 500,
  }) async {
    // FollowPuck owns the camera in rotate mode.
    if (rotateWithHeading) return;
    final map = _map;
    if (map == null) return;
    _lastFollowedLocation = location;
    _lastHeadingDeg = headingDeg;
    await map.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(location.longitude, location.latitude),
        ),
        zoom: clampMapboxZoom(zoom),
        bearing: _bearingForMode(headingDeg),
        pitch: _pitch,
        padding: _paddingForMode(),
      ),
      MapAnimationOptions(duration: durationMs),
    );
  }

  Future<LatLng?> currentCenter() async {
    final map = _map;
    if (map == null) return null;
    final camera = await map.getCameraState();
    final coords = camera.center.coordinates;
    return LatLng(coords.lat.toDouble(), coords.lng.toDouble());
  }

  Future<double?> currentZoom() async {
    final map = _map;
    if (map == null) return null;
    final camera = await map.getCameraState();
    return camera.zoom;
  }

  Future<void> enableLocationPuck() async {
    final map = _map;
    if (map == null) return;

    // Hide Mapbox chrome (compass / logo / info). Attribution still applies
    // via Mapbox ToS elsewhere (e.g. app About); ornaments are optional in SDK.
    await Future.wait([
      map.compass.updateSettings(CompassSettings(enabled: false)),
      map.logo.updateSettings(LogoSettings(enabled: false)),
      map.attribution.updateSettings(AttributionSettings(enabled: false)),
      map.scaleBar.updateSettings(ScaleBarSettings(enabled: false)),
    ]);

    const gold = Color(0xFFD4AF37);
    final puckImage = await _renderGoldLocationPuckPng(logicalSize: 28);
    final bearingImage = await _renderGoldLocationPuckPng(
      logicalSize: 28,
      withHeadingDot: true,
    );

    await map.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
        pulsingEnabled: true,
        pulsingColor: gold.toARGB32(),
        pulsingMaxRadius: 58,
        locationPuck: LocationPuck(
          locationPuck2D: LocationPuck2D(
            topImage: puckImage,
            bearingImage: bearingImage,
            scaleExpression: '["literal", 1.15]',
          ),
        ),
      ),
    );
  }
}

Future<Uint8List> _renderGoldLocationPuckPng({
  required double logicalSize,
  bool withHeadingDot = false,
}) async {
  const gold = Color(0xFFD4AF37);
  final pixelRatio = 3.0;
  final dim = (logicalSize * pixelRatio).round().clamp(48, 160);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(dim / 2, dim / 2);
  final radius = dim / 2 - pixelRatio * 2;

  canvas.drawCircle(
    center.translate(0, pixelRatio),
    radius,
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio),
  );
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = gold
      ..style = PaintingStyle.fill,
  );
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * pixelRatio,
  );
  canvas.drawCircle(
    Offset(center.dx - radius * 0.28, center.dy - radius * 0.28),
    radius * 0.22,
    Paint()..color = Colors.white.withValues(alpha: 0.45),
  );

  // White perimeter dot at the top; Mapbox rotates bearingImage with heading.
  if (withHeadingDot) {
    final dotRadius = radius * 0.28;
    final dotCenter = Offset(
      center.dx,
      center.dy - radius + dotRadius * 1.15,
    );
    canvas.drawCircle(
      dotCenter,
      dotRadius,
      Paint()..color = Colors.white,
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(dim, dim);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Failed to encode location puck PNG');
  }
  return bytes.buffer.asUint8List();
}
