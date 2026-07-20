import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import 'mapbox_site_annotations.dart';

/// Drives Mapbox camera for north-fixed (flat) or compass-follow (tilted) modes.
///
/// Heading / follow updates coalesce to the latest value so the camera stays
/// responsive instead of dropping frames while a previous [setCamera] is in flight.
class MapboxCameraCoordinator {
  MapboxMap? _map;
  double _lastHeadingDeg = 0;
  LatLng? _lastFollowedLocation;
  bool _headingInFlight = false;
  bool _followInFlight = false;
  double? _pendingHeadingDeg;
  LatLng? _pendingFollowLocation;
  double? _pendingFollowZoom;
  bool rotateWithHeading = false;

  /// Ignore heading jitter smaller than this (degrees).
  static const double headingEpsilonDeg = 0.25;

  void attach(MapboxMap map) {
    _map = map;
  }

  void detach() {
    _map = null;
    _lastFollowedLocation = null;
    _pendingHeadingDeg = null;
    _pendingFollowLocation = null;
    _pendingFollowZoom = null;
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
      ),
    );
  }

  /// Switch between north-fixed and heading-follow without remounting.
  Future<void> applyOrientationMode({
    required bool rotateWithHeading,
    required double headingDeg,
    double? zoom,
  }) async {
    this.rotateWithHeading = rotateWithHeading;
    final map = _map;
    if (map == null) return;
    _lastHeadingDeg = headingDeg;
    await map.setCamera(
      CameraOptions(
        bearing: _bearingForMode(headingDeg),
        pitch: _pitch,
        zoom: zoom != null ? clampMapboxZoom(zoom) : null,
      ),
    );
  }

  Future<void> applyHeading(double headingDeg, {bool force = false}) async {
    if (!rotateWithHeading) return;
    _pendingHeadingDeg = headingDeg;
    if (_headingInFlight) return;
    _headingInFlight = true;
    try {
      while (_pendingHeadingDeg != null) {
        final map = _map;
        if (map == null) return;
        final next = _pendingHeadingDeg!;
        _pendingHeadingDeg = null;
        if (!force && (next - _lastHeadingDeg).abs() < headingEpsilonDeg) {
          continue;
        }
        _lastHeadingDeg = next;
        await map.setCamera(
          CameraOptions(
            bearing: mapboxBearingFromHeading(next),
            pitch: _pitch,
          ),
        );
      }
    } finally {
      _headingInFlight = false;
    }
  }

  Future<void> followLocation(
    LatLng location, {
    required bool followUser,
    double? zoom,
  }) async {
    if (!followUser) return;
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
            zoom: nextZoom != null
                ? clampMapboxZoom(nextZoom)
                : (rotateWithHeading
                    ? clampMapboxZoom(MapConfig.mapboxRotateZoom)
                    : null),
            pitch: _pitch,
            bearing: _bearingForMode(_lastHeadingDeg),
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
      withChevron: true,
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
  bool withChevron = false,
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

  if (withChevron) {
    final tip = Offset(center.dx, center.dy - radius * 0.55);
    final left = Offset(center.dx - radius * 0.32, center.dy + radius * 0.05);
    final right = Offset(center.dx + radius * 0.32, center.dy + radius * 0.05);
    final chevron = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(center.dx, center.dy + radius * 0.08)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(
      chevron,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
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
