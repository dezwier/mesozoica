part of 'map_screen.dart';

/// Camera control, rotation, user-location following, and splash-screen
/// dismissal for [MapScreen].
mixin _MapScreenCameraMixin on State<MapScreen> {
  final MapboxCameraCoordinator _mapboxCamera = MapboxCameraCoordinator();
  final ValueNotifier<int> _rotateCardCount = ValueNotifier<int>(0);

  bool _mapboxReady = false;
  bool _splashDismissed = false;
  double _zoomLevel = MapConfig.mapboxRotateZoom;
  bool _didInitialCenter = false;
  bool _followUser = true;

  /// Continuous camera follow of the focused aerial-recon scout.
  bool _followAerialScout = false;

  /// True while the one-shot fly-to-recon animation is running (suppresses
  /// continuous follow so setCamera does not fight flyTo).
  bool _aerialFocusAnimating = false;

  /// false = north-fixed Mapbox; true = map bearing follows phone.
  bool _rotateMap = true;
  LatLng? _lastFollowedLocation;
  String? _mapboxBannerMessage;
  Timer? _splashSafetyTimer;
  VoidCallback? _aerialProgressListener;
  AerialSessionController? _aerialProgressBound;
  VoidCallback? _locationListenableListener;
  LocationService? _locationListenableBound;

  void _disposeCameraMixin() {
    _splashSafetyTimer?.cancel();
    _unbindAerialProgressListener();
    _unbindLocationListenable();
    _rotateCardCount.dispose();
  }

  void _bindAerialProgressListener() {
    final aerial = context.read<AerialSessionController>();
    if (_aerialProgressBound == aerial && _aerialProgressListener != null) {
      return;
    }
    _unbindAerialProgressListener();
    _aerialProgressBound = aerial;
    _aerialProgressListener = () {
      if (!mounted) return;
      _maybeFollowAerialScout();
    };
    aerial.progressTickListenable.addListener(_aerialProgressListener!);
  }

  void _unbindAerialProgressListener() {
    final aerial = _aerialProgressBound;
    final listener = _aerialProgressListener;
    if (aerial != null && listener != null) {
      aerial.progressTickListenable.removeListener(listener);
    }
    _aerialProgressBound = null;
    _aerialProgressListener = null;
  }

  void _bindLocationListenable() {
    final location = context.read<LocationService>();
    if (_locationListenableBound == location &&
        _locationListenableListener != null) {
      return;
    }
    _unbindLocationListenable();
    _locationListenableBound = location;
    _locationListenableListener = () {
      if (!mounted) return;
      _setInitialCamera(locationService: location);
      _maybeFollowUser(location);
    };
    location.locationListenable.addListener(_locationListenableListener!);
  }

  void _unbindLocationListenable() {
    final location = _locationListenableBound;
    final listener = _locationListenableListener;
    if (location != null && listener != null) {
      location.locationListenable.removeListener(listener);
    }
    _locationListenableBound = null;
    _locationListenableListener = null;
  }

  void _dismissSplash() {
    if (!mounted || _splashDismissed) return;
    _splashDismissed = true;
    _splashSafetyTimer?.cancel();
    context.read<SplashHoldController>().setInitialPageReady(true);
  }

  void _activateIfNeeded() {
    if (!widget.isActive) {
      // Site cards freeze the map UI but still want map-grade GPS so live
      // documentation progress on the card back keeps updating.
      context.read<LocationService>().setMapForeground(widget.highPrecisionGps);
      unawaited(context.read<LocationService>().setHeadingWanted(false));
      context.read<map_data.MapController>().pause();
      context.read<AerialSessionController>().stopTracking();
      _unbindAerialProgressListener();
      _unbindLocationListenable();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) return;
      // Soft freeze (field assistant): keep Mapbox markers warm, but stop
      // high-rate GPS / heading so the camera does not keep turning.
      context.read<LocationService>().setMapForeground(
        widget.highPrecisionGps && !widget.freezeMotion,
      );
      context.read<map_data.MapController>().load();
      if (widget.freezeMotion) {
        context.read<AerialSessionController>().stopTracking();
        _unbindAerialProgressListener();
      } else {
        context.read<AerialSessionController>().startTracking();
        _bindAerialProgressListener();
      }
      _bindLocationListenable();
      _syncHeadingWanted();
      _consumePendingFocus();
      _consumePendingAerialFocus();
      _consumePendingDrawCamera();
    });
  }

  /// FlutterCompass only while rotate mode or guidance needle needs it.
  void _syncHeadingWanted() {
    if (!mounted) return;
    final guidance = context.read<GuidanceSessionController>();
    final wanted =
        widget.isActive &&
        !widget.freezeMotion &&
        (_rotateMap || (guidance.isActive && guidance.showNeedle));
    unawaited(context.read<LocationService>().setHeadingWanted(wanted));
  }

  void _consumePendingFocus() {
    if (!widget.isActive || !_mapboxReady) return;
    final mapData = context.read<map_data.MapController>();
    final site = mapData.takePendingFocusSite();
    if (site == null) return;
    // Catalog backside map taps: select marker + slow pan, no card.
    mapData.selectSite(site);
    unawaited(_panToSite(site, durationMs: 1400, exitRotateMode: true));
  }

  void _consumePendingAerialFocus() {
    if (!widget.isActive || !_mapboxReady) return;
    final recon = context.read<AerialSessionController>();
    final session = recon.takePendingFocusSession();
    if (session == null) return;
    unawaited(_focusToolSession(session));
  }

  void _consumePendingDrawCamera() {
    if (!widget.isActive || !_mapboxReady) return;
    final recon = context.read<AerialSessionController>();
    if (!recon.isDrawMode) return;
    if (!recon.takePendingDrawCamera()) return;
    unawaited(_fitDrawModeCamera(recon));
  }

  /// North-fixed + zoom so screen height ≈ vehicle max route range.
  Future<void> _fitDrawModeCamera(AerialSessionController recon) async {
    if (!_mapboxReady) return;

    if (_rotateMap) {
      setState(() {
        _rotateMap = false;
        _followUser = true;
        _followAerialScout = false;
        _aerialFocusAnimating = false;
      });
      _mapboxCamera.clearPendingFollow();
      _syncHeadingWanted();
    } else {
      setState(() {
        _followAerialScout = false;
        _aerialFocusAnimating = false;
      });
      _mapboxCamera.clearPendingFollow();
    }
    // Guidance keeps running under the draw overlay (hidden while drawing).

    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_mapboxReady) return;
    if (!context.read<AerialSessionController>().isDrawMode) return;

    final location = context.read<LocationService>().currentLocation;
    if (location == null) return;

    final spanKm = recon.maxRouteKm;
    if (spanKm <= 0) return;

    await _mapboxCamera.fitVerticalSpanKm(location, spanKm, durationMs: 1200);
    if (!mounted) return;

    final zoom = await _mapboxCamera.currentZoom();
    if (!mounted || zoom == null) return;
    setState(() => _zoomLevel = clampMapboxZoom(zoom));
  }

  Future<void> _focusToolSession(ToolSession session) async {
    if (!_mapboxReady) return;

    if (_rotateMap) {
      setState(() {
        _rotateMap = false;
        _followUser = false;
        _followAerialScout = false;
        _aerialFocusAnimating = false;
      });
      _mapboxCamera.clearPendingFollow();
      _syncHeadingWanted();
    } else {
      setState(() {
        _followUser = false;
        _followAerialScout = false;
        _aerialFocusAnimating = false;
      });
      _mapboxCamera.clearPendingFollow();
    }

    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_mapboxReady) return;

    final recon = context.read<AerialSessionController>();
    final headingDeg = context.read<LocationService>().headingDeg;

    if (session.isPast) {
      if (session.route.isEmpty) return;
      await _mapboxCamera.fitRoute(
        session.route,
        durationMs: MapConfig.mapboxAerialSessionFocusDurationMs,
      );
      return;
    }

    final target =
        recon.scoutPosition(session) ??
        (session.route.isNotEmpty ? session.route.first : null);
    if (target == null) return;

    // Fly first without continuous follow — otherwise progress ticks call
    // setCamera mid-flyTo and the camera snaps once the scout has moved.
    final zoom = MapConfig.mapboxAerialSessionZoom;
    setState(() {
      _followAerialScout = true;
      _aerialFocusAnimating = true;
      _zoomLevel = zoom;
    });
    try {
      await _mapboxCamera.centerOn(
        target,
        zoom: zoom,
        headingDeg: headingDeg,
        durationMs: MapConfig.mapboxAerialSessionFocusDurationMs,
      );
    } finally {
      if (mounted) {
        setState(() => _aerialFocusAnimating = false);
        _maybeFollowAerialScout();
      } else {
        _aerialFocusAnimating = false;
      }
    }
  }

  void _maybeFollowAerialScout() {
    if (!_followAerialScout ||
        _aerialFocusAnimating ||
        !_mapboxReady ||
        _rotateMap) {
      return;
    }
    final recon = context.read<AerialSessionController>();
    final session = recon.focusedSession;
    if (session == null || !session.isActive) {
      setState(() => _followAerialScout = false);
      return;
    }
    final target = recon.scoutPosition(session);
    if (target == null) return;
    // Omit zoom so the slider can change level while we stay centered;
    // pan cancels follow via onFollowCancelled.
    unawaited(_mapboxCamera.followLocation(target, followUser: true));
  }

  Future<void> _panToSite(
    SiteSummary site, {
    int durationMs = 700,
    bool exitRotateMode = false,
  }) async {
    final lat = site.latitude;
    final lon = site.longitude;
    if (lat == null || lon == null || !_mapboxReady) return;
    final headingDeg = context.read<LocationService>().headingDeg;

    if (exitRotateMode && _rotateMap) {
      setState(() {
        _rotateMap = false;
        _followUser = false;
      });
      _mapboxCamera.clearPendingFollow();
      _syncHeadingWanted();
      // MapboxFieldMap exits FollowPuck → Idle + north-fixed camera.
    } else if (_rotateMap) {
      // Rotate mode stays locked on the user — don't pan away for site taps.
      return;
    } else {
      setState(() => _followUser = false);
      _mapboxCamera.clearPendingFollow();
    }

    // Wait for followUser=false / FollowPuck exit to settle before flyTo.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_mapboxReady) return;

    await _mapboxCamera.centerOn(
      LatLng(lat, lon),
      zoom: _zoomLevel,
      headingDeg: headingDeg,
      durationMs: durationMs,
    );
  }

  MapLocationFabMode get _locationFabMode {
    if (_rotateMap) return MapLocationFabMode.exitRotate;
    if (_followUser) return MapLocationFabMode.enterRotate;
    return MapLocationFabMode.center;
  }

  void _onLocationFabPressed(LocationService locationService) {
    switch (_locationFabMode) {
      case MapLocationFabMode.center:
        unawaited(_centerOnLocation(locationService));
      case MapLocationFabMode.enterRotate:
        _enterRotationMode();
      case MapLocationFabMode.exitRotate:
        _exitToNorthFixedCentered();
    }
  }

  void _enterRotationMode() {
    if (_rotateMap) return;
    if (!MapConfig.hasMapboxAccessToken) {
      setState(() {
        _mapboxBannerMessage =
            'Mapbox token missing — add MAPBOX_ACCESS_TOKEN via ./run.sh';
      });
      return;
    }
    setState(() {
      _rotateMap = true;
      _followUser = true;
      _followAerialScout = false;
      _aerialFocusAnimating = false;
      _zoomLevel = MapConfig.mapboxRotateZoom;
      _mapboxBannerMessage = null;
      final location = context.read<LocationService>().currentLocation;
      if (location != null) {
        _lastFollowedLocation = location;
      }
    });
    _syncHeadingWanted();
    // MapboxFieldMap switches FollowPuck ↔ Idle from rotateWithHeading.
  }

  void _exitToNorthFixedCentered() {
    if (!_rotateMap) return;
    setState(() {
      _rotateMap = false;
      _followUser = true;
      _followAerialScout = false;
      _aerialFocusAnimating = false;
      _zoomLevel = MapConfig.mapboxFollowZoom;
      _mapboxBannerMessage = null;
      final location = context.read<LocationService>().currentLocation;
      if (location != null) {
        _lastFollowedLocation = location;
      }
    });
    _syncHeadingWanted();
    // Stay in guidance: north-fixed follow still shows the vintage compass
    // (hidden again if the user pans away / leaves follow).
    // MapboxFieldMap switches FollowPuck ↔ Idle from rotateWithHeading.
  }

  /// After activating a guidance tool: keep rotate if already in it, otherwise
  /// center north-fixed on the user so overlays are visible.
  void _ensureGuidanceVisibleOnMap() {
    _syncHeadingWanted();
    if (_rotateMap) return;
    unawaited(_centerOnLocation(context.read<LocationService>()));
  }

  void _setInitialCamera({required LocationService locationService}) {
    if (!_mapboxReady || _didInitialCenter) return;
    if (!locationService.hasLocation) return;
    final location = locationService.currentLocation!;
    _didInitialCenter = true;
    _followUser = true;
    _lastFollowedLocation = location;
    if (_rotateMap) {
      // FollowPuck owns camera while rotating.
      _zoomLevel = MapConfig.mapboxRotateZoom;
      return;
    }
    final zoom = MapConfig.mapboxFollowZoom;
    unawaited(
      _mapboxCamera.centerOn(
        location,
        zoom: zoom,
        headingDeg: locationService.headingDeg,
      ),
    );
    _zoomLevel = zoom;
  }

  Future<void> _centerOnLocation(LocationService locationService) async {
    final location = locationService.currentLocation;
    if (location == null || !_mapboxReady || _rotateMap) return;
    setState(() {
      _followUser = true;
      _followAerialScout = false;
      _aerialFocusAnimating = false;
      _lastFollowedLocation = location;
      _zoomLevel = MapConfig.mapboxFollowZoom;
    });
    await _mapboxCamera.centerOn(
      location,
      zoom: MapConfig.mapboxFollowZoom,
      headingDeg: locationService.headingDeg,
      durationMs: 1200,
    );
  }

  void _maybeFollowUser(LocationService locationService) {
    // Rotate mode is owned by FollowPuck; only north-fixed GPS-follow here.
    if (_rotateMap || !_followUser || !_mapboxReady) return;
    final location = locationService.currentLocation;
    if (location == null) return;
    final previous = _lastFollowedLocation;
    if (previous != null &&
        previous.latitude == location.latitude &&
        previous.longitude == location.longitude) {
      return;
    }
    _lastFollowedLocation = location;
    unawaited(_mapboxCamera.followLocation(location, followUser: true));
  }

  void _onZoomChanged(double zoom) {
    if (_rotateMap) return;
    final clamped = clampMapboxZoom(zoom);
    setState(() => _zoomLevel = clamped);
    unawaited(_mapboxCamera.setZoom(clamped));
  }

  void _onMapboxZoomChanged(double zoom) {
    if (!mounted || _rotateMap) return;
    final clamped = clampMapboxZoom(zoom);
    if (clamped == _zoomLevel) return;
    setState(() => _zoomLevel = clamped);
  }

  void _onMapboxError(Object error) {
    if (!mounted) return;
    setState(() {
      _mapboxBannerMessage = 'Mapbox failed: $error';
    });
  }
}
