import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../services/token_storage.dart';
import 'map_perf_counters.dart';
import 'mapbox_site_annotations.dart';

const double _locationPuckLogicalSize = 32;
const double _locationPuckPixelRatio = 3;
const String _locationPuckFallbackAsset = 'assets/images/logo.png';

/// Brown pulse matching map chrome earth tones.
const Color locationPuckPulseBrown = Color(0xFF8D6E63);

/// Golden pulse for Ridge Glass added visibility range.
const Color locationPuckPulseGold = Color(0xFFD4AF37);

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
  double? _viewportWidth;
  bool rotateWithHeading = false;
  double? _lastPulseRadiusPx;
  Color _lastPulseColor = locationPuckPulseBrown;
  bool _lastPulsingEnabled = true;
  double _pulseVisibilityDistanceM = 20.0;
  double _pulseLatitudeDeg = 0.0;
  double _pulseZoom = MapConfig.mapboxFollowZoom;

  /// Cached so pulse-only updates do not fall back to Mapbox's blue default puck.
  Uint8List? _puckTopImage;
  Uint8List? _puckBearingImage;
  Uint8List? _puckShadowImage;

  /// Bumped on every Mapbox camera frame so Flutter overlays can reproject
  /// in lockstep with pan / FollowPuck (without a slow polling timer).
  final ValueNotifier<int> cameraMotionEpoch = ValueNotifier<int>(0);

  void notifyCameraMotion() {
    cameraMotionEpoch.value++;
  }

  void attach(MapboxMap map) {
    _map = map;
  }

  void detach() {
    _map = null;
    _lastFollowedLocation = null;
    _pendingFollowLocation = null;
    _pendingFollowZoom = null;
    _pulseSyncTrailing?.cancel();
    _pulseSyncTrailing = null;
    _lastPulseSyncAt = null;
    _probeCache = null;
    _lastPulseRadiusPx = null;
    _puckTopImage = null;
    _puckBearingImage = null;
    _puckShadowImage = null;
  }

  MapboxMap? get map => _map;

  /// Convert a Flutter logical pixel (in the map widget) to WGS84.
  Future<LatLng?> coordinateForPixel(Offset pixel) async {
    final map = _map;
    if (map == null) return null;
    final point = await map.coordinateForPixel(
      ScreenCoordinate(x: pixel.dx, y: pixel.dy),
    );
    final coords = point.coordinates;
    return LatLng(coords.lat.toDouble(), coords.lng.toDouble());
  }

  /// Project WGS84 points to Flutter logical pixels in the map widget.
  Future<List<Offset?>> pixelsForCoordinates(List<LatLng> points) async {
    final map = _map;
    if (map == null || points.isEmpty) {
      return List<Offset?>.filled(points.length, null);
    }
    final geo = [
      for (final p in points)
        Point(coordinates: Position(p.longitude, p.latitude)),
    ];
    try {
      MapPerfCounters.countChannelCall();
      final pixels = await map.pixelsForCoordinates(geo);
      return [
        for (final pixel in pixels)
          pixel == null ? null : Offset(pixel.x.toDouble(), pixel.y.toDouble()),
      ];
    } catch (_) {
      return List<Offset?>.filled(points.length, null);
    }
  }

  /// Logical map height from Flutter layout (preferred over [MapboxMap.getSize]).
  void setViewportHeight(double height) {
    if (height <= 0) return;
    _viewportHeight = height;
  }

  /// Logical map size from Flutter layout (for visible-bounds sampling).
  void setViewportSize({required double width, required double height}) {
    if (width <= 0 || height <= 0) return;
    _viewportWidth = width;
    _viewportHeight = height;
  }

  /// Last layout size of the map widget, if known.
  ui.Size? get viewportSize {
    final width = _viewportWidth;
    final height = _viewportHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return ui.Size(width, height);
  }

  /// Approximate WGS84 bounds of the visible map (corners via screen→geo).
  Future<LatLngBounds?> visibleBounds() async {
    final map = _map;
    final width = _viewportWidth;
    final height = _viewportHeight;
    if (map == null || width == null || height == null) return null;
    final corners = await Future.wait([
      coordinateForPixel(Offset.zero),
      coordinateForPixel(Offset(width, 0)),
      coordinateForPixel(Offset(0, height)),
      coordinateForPixel(Offset(width, height)),
    ]);
    final points = corners.whereType<LatLng>().toList();
    if (points.length < 4) return null;
    return LatLngBounds.fromPoints(points);
  }

  /// Drop queued GPS follow so a programmatic [centerOn] is not overwritten.
  void clearPendingFollow() {
    _pendingFollowLocation = null;
    _pendingFollowZoom = null;
  }

  double get _pitch => mapboxPitchForMode(rotateWithHeading: rotateWithHeading);

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
    await map.flyTo(options, MapAnimationOptions(duration: durationMs));
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
            center: Point(coordinates: Position(next.longitude, next.latitude)),
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

  /// Fit the camera to a route polyline (north-fixed).
  Future<void> fitRoute(
    List<LatLng> route, {
    int durationMs = 1200,
    double padding = 56,
  }) async {
    if (rotateWithHeading) return;
    final map = _map;
    if (map == null || route.isEmpty) return;
    clearPendingFollow();
    final points = <Point>[
      for (final p in route)
        Point(coordinates: Position(p.longitude, p.latitude)),
    ];
    final options = await map.cameraForCoordinatesPadding(
      points,
      CameraOptions(bearing: 0, pitch: 0),
      MbxEdgeInsets(
        top: padding + 72,
        left: padding,
        bottom: padding + 72,
        right: padding,
      ),
      null,
      null,
    );
    if (options.center != null) {
      final coords = options.center!.coordinates;
      _lastFollowedLocation = LatLng(
        coords.lat.toDouble(),
        coords.lng.toDouble(),
      );
    }
    await map.flyTo(options, MapAnimationOptions(duration: durationMs));
  }

  /// Zoom so the visible map height is approximately [spanKm], centered on
  /// [center] (north-fixed). Used when entering aerial draw mode so
  /// the screen height matches the vehicle's max route range.
  Future<void> fitVerticalSpanKm(
    LatLng center,
    double spanKm, {
    int durationMs = 1200,
  }) async {
    if (rotateWithHeading) return;
    final map = _map;
    if (map == null || spanKm <= 0) return;
    clearPendingFollow();

    const distance = Distance();
    final halfM = spanKm * 500;
    final north = distance.offset(center, halfM, 0);
    final south = distance.offset(center, halfM, 180);
    // Thin E–W extent so the N–S span is the constraining dimension (screen
    // height ≈ [spanKm]), not a square that would letterbox on portrait.
    final halfWidthM = halfM * 0.01 < 1.0 ? 1.0 : halfM * 0.01;
    final corners = <LatLng>[
      distance.offset(north, halfWidthM, 270),
      distance.offset(north, halfWidthM, 90),
      distance.offset(south, halfWidthM, 270),
      distance.offset(south, halfWidthM, 90),
    ];
    final points = <Point>[
      for (final p in corners)
        Point(coordinates: Position(p.longitude, p.latitude)),
    ];
    final options = await map.cameraForCoordinatesPadding(
      points,
      CameraOptions(bearing: 0, pitch: 0),
      MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
      null,
      null,
    );
    _lastFollowedLocation = center;
    await map.flyTo(options, MapAnimationOptions(duration: durationMs));
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

  /// Current pitch/bearing in degrees (Mapbox camera state).
  Future<({double pitch, double bearing})?> currentAttitude() async {
    final map = _map;
    if (map == null) return null;
    try {
      final camera = await map.getCameraState();
      return (pitch: camera.pitch, bearing: camera.bearing);
    } catch (_) {
      return null;
    }
  }

  /// Avatar puck with ground shadow, white heading arrow, and brown pulse.
  ///
  /// [visibilityDistanceM] is the effective site-discovery radius (main param
  /// after level/tool boosts). The pulse max radius is that ground distance
  /// projected to screen pixels at [center].
  Future<void> enableLocationPuck({
    String? avatarImageUrl,
    double? visibilityDistanceM,
    LatLng? center,
    double? latitudeDeg,
    double? zoom,
    Color? pulseColor,
    bool pulsingEnabled = true,
  }) async {
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
    try {
      puckImage = await _renderAvatarLocationPuckPng(
        logicalSize: _locationPuckLogicalSize,
        avatar: avatar,
      );
    } finally {
      avatar?.dispose();
    }
    final bearingImage = await _renderHeadingArrowPng(
      logicalSize: _locationPuckLogicalSize,
    );
    final shadowImage = await _renderLocationPuckShadowPng(
      logicalSize: _locationPuckLogicalSize,
    );
    _puckTopImage = puckImage;
    _puckBearingImage = bearingImage;
    _puckShadowImage = shadowImage;

    // Quantised like [syncLocationPuckPulse] so the epsilon check that guards
    // later pushes compares against the same baseline.
    final pulsePx = (await _resolvePulseRadiusPx(
      visibilityDistanceM: visibilityDistanceM,
      center: center,
      latitudeDeg: latitudeDeg,
      zoom: zoom,
    )).roundToDouble();
    _lastPulseRadiusPx = pulsePx;
    _lastPulseColor = pulseColor ?? locationPuckPulseBrown;
    _lastPulsingEnabled = pulsingEnabled;
    _lastPulseSyncAt = DateTime.now();

    await map.location.updateSettings(
      _locationPuckSettings(
        pulsePx: pulsePx,
        pulseColor: _lastPulseColor,
        pulsingEnabled: pulsingEnabled,
      ),
    );
  }

  /// Smallest pulse-radius change worth a settings push, in logical pixels.
  ///
  /// Every push re-serialises the three puck PNGs across the platform channel
  /// and forces a native texture re-upload, so sub-pixel GPS jitter must not
  /// trigger one. The pulse is a soft translucent ring — 2 px is invisible.
  static const double pulseRadiusEpsilonPx = 2.0;

  /// Fastest cadence for pulse-only settings pushes.
  static const Duration pulseSyncMinInterval = Duration(milliseconds: 250);

  DateTime? _lastPulseSyncAt;
  Timer? _pulseSyncTrailing;
  bool _pulseSyncInFlight = false;

  /// Update the discovery pulse radius (zoom / visibility / location).
  ///
  /// Always re-applies the cached avatar puck: Mapbox Flutter replaces a null
  /// [LocationComponentSettings.locationPuck] with the blue default 2D puck.
  ///
  /// Rate-limited to [pulseSyncMinInterval] with a trailing call, so a
  /// pinch-zoom produces a handful of pushes rather than one per camera frame.
  Future<void> syncLocationPuckPulse({
    double? visibilityDistanceM,
    LatLng? center,
    double? latitudeDeg,
    double? zoom,
    Color? pulseColor,
    bool? pulsingEnabled,
  }) async {
    if (_map == null || _puckTopImage == null) return;

    final last = _lastPulseSyncAt;
    final sinceLast = last == null ? null : DateTime.now().difference(last);
    if (_pulseSyncInFlight ||
        (sinceLast != null && sinceLast < pulseSyncMinInterval)) {
      // Coalesce: re-run once with the newest camera/location after the window.
      // Floor the delay — a call arriving while one is in flight can already be
      // past the window, and a zero/negative timer would spin.
      final remaining = sinceLast == null
          ? pulseSyncMinInterval
          : pulseSyncMinInterval - sinceLast;
      _pulseSyncTrailing?.cancel();
      _pulseSyncTrailing = Timer(
        remaining < const Duration(milliseconds: 16)
            ? const Duration(milliseconds: 16)
            : remaining,
        () {
          _pulseSyncTrailing = null;
          unawaited(
            syncLocationPuckPulse(
              visibilityDistanceM: visibilityDistanceM,
              center: center,
              latitudeDeg: latitudeDeg,
              zoom: zoom,
              pulseColor: pulseColor,
              pulsingEnabled: pulsingEnabled,
            ),
          );
        },
      );
      return;
    }

    _pulseSyncInFlight = true;
    try {
      final resolved = await _resolvePulseRadiusPx(
        visibilityDistanceM: visibilityDistanceM,
        center: center,
        latitudeDeg: latitudeDeg,
        zoom: zoom,
      );
      final map = _map;
      if (map == null) return;
      // Quantise so a drifting projection settles instead of oscillating.
      final pulsePx = resolved.roundToDouble();
      final color = pulseColor ?? locationPuckPulseBrown;
      final enabled = pulsingEnabled ?? _lastPulsingEnabled;
      final previous = _lastPulseRadiusPx;
      final colorChanged = color.toARGB32() != _lastPulseColor.toARGB32();
      final enabledChanged = enabled != _lastPulsingEnabled;
      if (previous != null &&
          (pulsePx - previous).abs() < pulseRadiusEpsilonPx &&
          !colorChanged &&
          !enabledChanged) {
        return;
      }
      _lastPulseRadiusPx = pulsePx;
      _lastPulseColor = color;
      _lastPulsingEnabled = enabled;
      _lastPulseSyncAt = DateTime.now();
      await map.location.updateSettings(
        _locationPuckSettings(
          pulsePx: pulsePx,
          pulseColor: color,
          pulsingEnabled: enabled,
        ),
      );
    } finally {
      _pulseSyncInFlight = false;
    }
  }

  /// Project a ground radius in meters to screen pixels at [center].
  Future<double?> projectGroundRadiusPx({
    required LatLng center,
    required double radiusM,
  }) => _projectGroundRadiusPx(center: center, radiusM: radiusM);

  LocationComponentSettings _locationPuckSettings({
    required double pulsePx,
    required Color pulseColor,
    required bool pulsingEnabled,
  }) {
    return LocationComponentSettings(
      enabled: true,
      puckBearingEnabled: true,
      puckBearing: PuckBearing.HEADING,
      pulsingEnabled: pulsingEnabled,
      pulsingColor: pulseColor.toARGB32(),
      pulsingMaxRadius: pulsePx,
      locationPuck: LocationPuck(
        locationPuck2D: LocationPuck2D(
          topImage: _puckTopImage,
          bearingImage: _puckBearingImage,
          shadowImage: _puckShadowImage,
          scaleExpression: '["literal", 1.1]',
          opacity: 1,
        ),
      ),
    );
  }

  /// Prefer Mapbox projection (same approach as terrain-echo); Mercator fallback.
  Future<double> _resolvePulseRadiusPx({
    double? visibilityDistanceM,
    LatLng? center,
    double? latitudeDeg,
    double? zoom,
  }) async {
    if (visibilityDistanceM != null && visibilityDistanceM > 0) {
      _pulseVisibilityDistanceM = visibilityDistanceM;
    }
    if (zoom != null) {
      _pulseZoom = zoom;
    }
    final origin =
        center ?? (latitudeDeg != null ? LatLng(latitudeDeg, 0) : null);
    if (origin != null) {
      _pulseLatitudeDeg = origin.latitude;
    } else if (latitudeDeg != null) {
      _pulseLatitudeDeg = latitudeDeg;
    }

    if (origin != null && center != null) {
      // The probe is a platform-channel round-trip; its result only depends on
      // these three inputs, so an unchanged call can reuse the last answer.
      final cached = _probeCache;
      if (cached != null &&
          cached.radiusM == _pulseVisibilityDistanceM &&
          cached.zoom == _pulseZoom &&
          cached.center.latitude == center.latitude &&
          cached.center.longitude == center.longitude) {
        return cached.px;
      }
      final projected = await _projectGroundRadiusPx(
        center: center,
        radiusM: _pulseVisibilityDistanceM,
      );
      if (projected != null) {
        _probeCache = (
          center: center,
          zoom: _pulseZoom,
          radiusM: _pulseVisibilityDistanceM,
          px: projected,
        );
        return projected;
      }
    }

    return MapConfig.groundRadiusToPulsePx(
      radiusM: _pulseVisibilityDistanceM,
      latitudeDeg: _pulseLatitudeDeg,
      zoom: _pulseZoom,
    );
  }

  /// Last successful ground-radius probe, keyed by its inputs.
  ({LatLng center, double zoom, double radiusM, double px})? _probeCache;

  /// Scale a short lateral probe to [radiusM] via Mapbox screen projection.
  Future<double?> _projectGroundRadiusPx({
    required LatLng center,
    required double radiusM,
  }) async {
    final probeM = math.min(12.0, radiusM * 0.2).clamp(4.0, 12.0);
    final probe = _offsetMetersEast(center, probeM);
    final pixels = await pixelsForCoordinates([center, probe]);
    if (pixels.length < 2) return null;
    final originPx = pixels[0];
    final probePx = pixels[1];
    if (originPx == null || probePx == null) return null;
    final probeDist = (probePx - originPx).distance;
    if (probeDist < 0.5) return null;
    return (probeDist * (radiusM / probeM)).clamp(8.0, 4096.0);
  }

  static LatLng _offsetMetersEast(LatLng origin, double eastM) {
    final latRad = origin.latitude * math.pi / 180.0;
    final metersPerDegLon = 111320.0 * math.cos(latRad).abs().clamp(0.01, 1.0);
    final dLon = eastM / metersPerDegLon;
    return LatLng(origin.latitude, origin.longitude + dLon);
  }
}

({int dim, Offset center, double radius, double borderWidth}) _puckGeometry(
  double logicalSize,
) {
  const pixelRatio = _locationPuckPixelRatio;
  final dim = (logicalSize * pixelRatio * 1.6).round().clamp(64, 192);
  final center = Offset(dim / 2, dim / 2);
  final radius = logicalSize * pixelRatio * 0.38;
  final borderWidth = 2.5 * pixelRatio;
  return (dim: dim, center: center, radius: radius, borderWidth: borderWidth);
}

Future<ui.Image?> _loadLocationPuckAvatar(String? imageUrl) async {
  if (imageUrl != null && imageUrl.isNotEmpty) {
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

Future<Uint8List> _renderLocationPuckShadowPng({
  required double logicalSize,
}) async {
  const pixelRatio = _locationPuckPixelRatio;
  final geo = _puckGeometry(logicalSize);
  final dim = geo.dim;
  final center = geo.center;
  final radius = geo.radius;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawOval(
    Rect.fromCenter(
      center: center.translate(0, radius * 0.15),
      width: radius * 2.4,
      height: radius * 1.15,
    ),
    Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio * 2.2),
  );

  return _encodePng(recorder, dim);
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

  // Soft drop shadow for depth.
  canvas.drawCircle(
    center.translate(0, pixelRatio * 1.4),
    radius,
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio * 1.6),
  );

  final innerRadius = radius - borderWidth / 2;

  canvas.drawCircle(center, innerRadius, Paint()..color = Colors.white);

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

/// Transparent PNG with a white heading arrow; Mapbox rotates this layer.
Future<Uint8List> _renderHeadingArrowPng({required double logicalSize}) async {
  const pixelRatio = _locationPuckPixelRatio;
  final geo = _puckGeometry(logicalSize);
  final dim = geo.dim;
  final center = geo.center;
  final radius = geo.radius;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final tip = Offset(center.dx, center.dy - radius * 0.55);
  final left = Offset(center.dx - radius * 0.32, center.dy + radius * 0.38);
  final right = Offset(center.dx + radius * 0.32, center.dy + radius * 0.38);
  final notch = Offset(center.dx, center.dy + radius * 0.12);

  final path = ui.Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(right.dx, right.dy)
    ..lineTo(notch.dx, notch.dy)
    ..lineTo(left.dx, left.dy)
    ..close();

  canvas.drawPath(
    path,
    Paint()
      ..color = const Color(0x44000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio * 0.6),
  );
  canvas.drawPath(path, Paint()..color = Colors.white);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * pixelRatio
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
