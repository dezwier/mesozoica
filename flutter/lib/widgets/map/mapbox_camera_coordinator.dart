import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../services/token_storage.dart';
import 'mapbox_site_annotations.dart';

const Color _locationPuckGold = Color(0xFFD4AF37);
const double _locationPuckLogicalSize = 28;
const double _locationPuckPixelRatio = 3;
const String _locationPuckFallbackAsset = 'assets/images/logo.png';

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
  /// pitch/bearing/zoom. Exiting animates to a flat, north-up camera (same
  /// duration as FollowPuck enter) so leaving rotate mode isn't a snap.
  Future<void> applyOrientationMode({
    required bool rotateWithHeading,
    required double headingDeg,
    double? zoom,
    int durationMs = 1200,
  }) async {
    this.rotateWithHeading = rotateWithHeading;
    _lastHeadingDeg = headingDeg;
    if (rotateWithHeading) return;
    final map = _map;
    if (map == null) return;
    // Drop any coalesced GPS follow so it can't interrupt this flyTo.
    clearPendingFollow();
    final options = CameraOptions(
      bearing: 0,
      pitch: 0,
      zoom: zoom != null ? clampMapboxZoom(zoom) : null,
      padding: _paddingForMode(),
    );
    if (durationMs <= 0) {
      await map.setCamera(options);
      return;
    }
    await map.flyTo(
      options,
      MapAnimationOptions(duration: durationMs),
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

  /// Avatar circle puck (chrome-style shadow + white border) with a heading
  /// triangle. Avatar stays upright; only the triangle rotates with bearing.
  Future<void> enableLocationPuck({String? avatarImageUrl}) async {
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

    final avatar = await _loadLocationPuckAvatar(avatarImageUrl);
    late final Uint8List puckImage;
    late final Uint8List bearingImage;
    try {
      puckImage = await _renderAvatarLocationPuckPng(
        logicalSize: _locationPuckLogicalSize,
        avatar: avatar,
      );
      // Triangle-only layer; Mapbox rotates this on top of [topImage].
      bearingImage = await _renderHeadingTrianglePng(
        logicalSize: _locationPuckLogicalSize,
      );
    } finally {
      avatar?.dispose();
    }

    await map.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
        pulsingEnabled: false,
        locationPuck: LocationPuck(
          locationPuck2D: LocationPuck2D(
            topImage: puckImage,
            bearingImage: bearingImage,
            // Disable Mapbox's default shadow image (we bake our own).
            shadowImage: Uint8List.fromList(const []),
            scaleExpression: '["literal", 1.15]',
            opacity: 1,
          ),
        ),
      ),
    );
  }
}

Future<ui.Image?> _loadLocationPuckAvatar(String? imageUrl) async {
  if (imageUrl != null && imageUrl.isNotEmpty) {
    // Same provider/cache as the chrome profile button.
    final cached = await _imageFromProvider(
      CachedNetworkImageProvider(imageUrl),
    );
    if (cached != null) return cached;

    try {
      final token = await TokenStorage.loadToken();
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return _decodeUiImage(response.bodyBytes);
      }
    } catch (_) {}
  }
  try {
    final data = await rootBundle.load(_locationPuckFallbackAsset);
    return _decodeUiImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> _imageFromProvider(ImageProvider provider) async {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(info.image.clone());
      }
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(
    const Duration(seconds: 8),
    onTimeout: () {
      stream.removeListener(listener);
      return null;
    },
  );
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Circle stays the same pixel radius as before; [dim] grows so the heading
/// triangle can sit outside without clipping. On-screen circle size is
/// `radius * scale` (independent of padding).
({
  int dim,
  Offset center,
  double radius,
  double borderWidth,
}) _puckGeometry(double logicalSize) {
  const pixelRatio = _locationPuckPixelRatio;
  final circleSpan = (logicalSize * pixelRatio).round().clamp(48, 160);
  final radius = circleSpan / 2 - pixelRatio * 2;
  // Room outside the rim for the heading triangle (+ stroke / shadow).
  final outerPad = radius * 0.55;
  final dim = (circleSpan + 2 * outerPad).round();
  final center = Offset(dim / 2, dim / 2);
  // Matches map chrome circle buttons (white border width 2.5).
  final borderWidth = 2.5 * pixelRatio;
  return (
    dim: dim,
    center: center,
    radius: radius,
    borderWidth: borderWidth,
  );
}

Future<Uint8List> _renderAvatarLocationPuckPng({
  required double logicalSize,
  ui.Image? avatar,
}) async {
  const pixelRatio = _locationPuckPixelRatio;
  final geo = _puckGeometry(logicalSize);
  final dim = geo.dim;
  final center = geo.center;
  final radius = geo.radius;
  final borderWidth = geo.borderWidth;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // Soft drop shadow — same idea as Material elevation on chrome buttons.
  canvas.drawCircle(
    center.translate(0, pixelRatio * 1.2),
    radius,
    Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio * 1.4),
  );

  final innerRadius = radius - borderWidth / 2;

  // Opaque disc so the photo never shows the map through it.
  canvas.drawCircle(
    center,
    innerRadius,
    Paint()..color = Colors.white,
  );

  canvas.save();
  canvas.clipPath(
    ui.Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius)),
  );
  if (avatar != null) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromCircle(center: center, radius: innerRadius),
      image: avatar,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      isAntiAlias: true,
    );
  }
  canvas.restore();

  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth,
  );

  return _encodePng(recorder, dim);
}

/// Transparent PNG with a heading triangle sitting outside the puck circle.
Future<Uint8List> _renderHeadingTrianglePng({
  required double logicalSize,
}) async {
  const pixelRatio = _locationPuckPixelRatio;
  final geo = _puckGeometry(logicalSize);
  final dim = geo.dim;
  final center = geo.center;
  final radius = geo.radius;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final height = radius * 0.4;
  final halfWidth = radius * 0.3;
  // Base on the outer rim; tip points outward (away from avatar).
  final baseY = center.dy - radius;
  final tip = Offset(center.dx, baseY - height);
  final path = ui.Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + halfWidth, baseY)
    ..lineTo(tip.dx - halfWidth, baseY)
    ..close();

  canvas.drawPath(
    path,
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio * 0.7),
  );
  canvas.drawPath(path, Paint()..color = _locationPuckGold);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * pixelRatio
      ..strokeJoin = StrokeJoin.round,
  );

  return _encodePng(recorder, dim);
}

Future<Uint8List> _encodePng(ui.PictureRecorder recorder, int dim) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(dim, dim);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Failed to encode location puck PNG');
  }
  return bytes.buffer.asUint8List();
}
