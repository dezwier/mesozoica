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

  void _disposeCameraMixin() {
    _splashSafetyTimer?.cancel();
    _rotateCardCount.dispose();
  }

  void _dismissSplash() {
    if (!mounted || _splashDismissed) return;
    _splashDismissed = true;
    _splashSafetyTimer?.cancel();
    context.read<SplashHoldController>().setInitialPageReady(true);
  }

  void _activateIfNeeded() {
    if (!widget.isActive) {
      context.read<LocationService>().setMapForeground(false);
      context.read<map_data.MapController>().pause();
      context.read<AerialMissionController>().stopTracking();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) return;
      context.read<LocationService>().setMapForeground(true);
      context.read<map_data.MapController>().load();
      context.read<AerialMissionController>().startTracking();
      _consumePendingFocus();
      _consumePendingAerialFocus();
    });
  }

  void _consumePendingFocus() {
    if (!widget.isActive || !_mapboxReady) return;
    final mapData = context.read<map_data.MapController>();
    final site = mapData.takePendingFocusSite();
    if (site == null) return;
    // Catalog backside map taps: select marker + slow pan, no card.
    mapData.selectSite(site);
    unawaited(
      _panToSite(
        site,
        durationMs: 1400,
        exitRotateMode: true,
      ),
    );
  }

  void _consumePendingAerialFocus() {
    if (!widget.isActive || !_mapboxReady) return;
    final recon = context.read<AerialMissionController>();
    final mission = recon.takePendingFocusMission();
    if (mission == null) return;
    unawaited(_focusAerialMission(mission));
  }

  Future<void> _focusAerialMission(AerialMission mission) async {
    if (!_mapboxReady) return;

    if (_rotateMap) {
      setState(() {
        _rotateMap = false;
        _followUser = false;
        _followAerialScout = false;
        _aerialFocusAnimating = false;
      });
      _mapboxCamera.clearPendingFollow();
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

    final recon = context.read<AerialMissionController>();
    final headingDeg = context.read<LocationService>().headingDeg;

    if (mission.isPast) {
      if (mission.route.isEmpty) return;
      await _mapboxCamera.fitRoute(
        mission.route,
        durationMs: MapConfig.mapboxAerialMissionFocusDurationMs,
      );
      return;
    }

    final target = recon.scoutPosition(mission) ??
        (mission.route.isNotEmpty ? mission.route.first : null);
    if (target == null) return;

    // Fly first without continuous follow — otherwise progress ticks call
    // setCamera mid-flyTo and the camera snaps once the scout has moved.
    final zoom = MapConfig.mapboxAerialMissionZoom;
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
        durationMs: MapConfig.mapboxAerialMissionFocusDurationMs,
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
    final recon = context.read<AerialMissionController>();
    final mission = recon.focusedMission;
    if (mission == null || !mission.isActive) {
      setState(() => _followAerialScout = false);
      return;
    }
    // Rebuild trigger while flying (progressTick) so follow stays live.
    // ignore: unused_local_variable
    final tick = recon.progressTick;
    final target = recon.scoutPosition(mission);
    if (target == null) return;
    // Omit zoom so the slider can change level while we stay centered;
    // pan cancels follow via onFollowCancelled.
    unawaited(
      _mapboxCamera.followLocation(
        target,
        followUser: true,
      ),
    );
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

  void _toggleRotationMode() {
    if (!MapConfig.hasMapboxAccessToken) {
      setState(() {
        _mapboxBannerMessage =
            'Mapbox token missing — add MAPBOX_ACCESS_TOKEN via ./run.sh';
      });
      return;
    }
    final enteringRotate = !_rotateMap;
    setState(() {
      _rotateMap = enteringRotate;
      _mapboxBannerMessage = null;
      if (enteringRotate) {
        _followUser = true;
        _zoomLevel = MapConfig.mapboxRotateZoom;
        final location = context.read<LocationService>().currentLocation;
        if (location != null) {
          _lastFollowedLocation = location;
        }
      }
    });
    // MapboxFieldMap switches FollowPuck ↔ Idle from rotateWithHeading.
  }

  void _setInitialCamera({
    required LocationService locationService,
  }) {
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
    unawaited(
      _mapboxCamera.followLocation(
        location,
        followUser: true,
      ),
    );
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
