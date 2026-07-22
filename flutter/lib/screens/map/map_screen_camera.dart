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
    context.read<SplashHoldProvider>().setInitialPageReady(true);
  }

  void _activateIfNeeded() {
    if (!widget.isActive) {
      context.read<LocationService>().setMapForeground(false);
      context.read<map_data.MapController>().pause();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) return;
      context.read<LocationService>().setMapForeground(true);
      context.read<map_data.MapController>().load();
      _consumePendingFocus();
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
