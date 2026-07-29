import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../config/game_config.dart';
import '../../controllers/aerial_mission_controller.dart';
import '../../controllers/formation_map_controller.dart';
import '../../models/site.dart';
import '../../utils/formation_map_raster.dart';
import 'mapbox_aerial_mission_annotations.dart';
import 'mapbox_basemap_config.dart';
import 'mapbox_camera_coordinator.dart';
import 'mapbox_formation_map_overlay.dart';
import 'mapbox_site_annotations.dart';
import 'mapbox_viewport_native.dart';
import 'map_center_crosshair.dart';
import 'map_rotate_site_card_overlay.dart';

typedef MapSiteTapCallback = void Function(SiteSummary site);

/// Mapbox Standard field map — basemap theme + day/dusk from app appearance.
///
/// [rotateWithHeading] false = north-fixed; true = native FollowPuck + heading.
class MapboxFieldMap extends StatefulWidget {
  const MapboxFieldMap({
    super.key,
    required this.camera,
    required this.rotateWithHeading,
    required this.sites,
    required this.selectedSite,
    required this.markerDatasetKey,
    required this.currentLocation,
    required this.headingDeg,
    required this.followUser,
    required this.initialCenter,
    required this.initialZoom,
    required this.basemapTheme,
    required this.brightness,
    required this.onSiteTap,
    required this.onFollowCancelled,
    required this.onZoomChanged,
    required this.onReadyChanged,
    required this.onRotatePinchZoomOut,
    required this.onLocationPuckTap,
    this.mapActive = true,
    this.avatarImageUrl,
    this.hiddenRotateSiteId,
    this.rotateCardCount,
    this.headingListenable,
    this.aerialRecon,
    this.formationMap,
    this.showPastAerialRoutes = false,
    this.showAerialReconOverlays = true,
    this.onError,
    this.onMapIdle,
  });

  final MapboxCameraCoordinator camera;
  final bool rotateWithHeading;
  /// When false (catalog/profile/tools open), pause rotate overlay work.
  final bool mapActive;
  final List<SiteSummary> sites;
  final SiteSummary? selectedSite;
  /// Changes on archive ↔ field ↔ show-all (and filters) → wipe + reload.
  final String markerDatasetKey;
  final LatLng? currentLocation;
  final double headingDeg;
  /// Live heading without rebuilding this widget (compass decoupled).
  final ValueListenable<double>? headingListenable;
  final bool followUser;
  final LatLng initialCenter;
  final double initialZoom;
  final MapboxBasemapTheme basemapTheme;
  /// App appearance — drives Mapbox `lightPreset` day vs dusk.
  final Brightness brightness;
  final MapSiteTapCallback onSiteTap;
  final VoidCallback onFollowCancelled;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<bool> onReadyChanged;
  /// Pinch-out in rotate mode → exit to north-fixed centered (mode 2).
  final VoidCallback onRotatePinchZoomOut;
  /// Tap the location puck in north-fixed mode → enter rotate (mode 3).
  final VoidCallback onLocationPuckTap;
  /// Profile image for the location puck (falls back to app logo).
  final String? avatarImageUrl;
  /// Hide this site's mini-card while the detail sheet morphs open.
  final int? hiddenRotateSiteId;
  /// Optional admin HUD counter for visible rotate mini-cards.
  final ValueNotifier<int>? rotateCardCount;
  /// Ongoing + past aerial recon routes / scout puck.
  final AerialMissionController? aerialRecon;
  /// Timed Formation Map period mosaic.
  final FormationMapController? formationMap;
  /// When true, draw past (done/cancelled) recon routes from the last 24h.
  final bool showPastAerialRoutes;
  /// When false (archive mode), never draw recon routes or scout.
  final bool showAerialReconOverlays;
  final ValueChanged<Object>? onError;
  /// Fired when the map becomes idle (after pan/zoom settle).
  final VoidCallback? onMapIdle;

  @override
  State<MapboxFieldMap> createState() => _MapboxFieldMapState();
}

class _MapboxFieldMapState extends State<MapboxFieldMap>
    with SingleTickerProviderStateMixin {
  MapboxSiteAnnotations? _annotations;
  MapboxAerialMissionAnnotations? _aerialReconAnnotations;
  final MapboxFormationMapOverlay _formationOverlay = MapboxFormationMapOverlay();
  MapboxMap? _map;
  int _lastFormationSitesRevision = -1;
  bool _ready = false;
  bool _readyNotified = false;
  bool _styleLoaded = false;
  bool _cameraSeeded = false;
  bool _seeding = false;
  bool _tokenReady = false;
  Timer? _annotationDebounce;
  Timer? _readyTimeout;
  Timer? _readyNotifyFallback;
  Timer? _followPuckReassertTimer;
  Timer? _locationPuckTapTimer;
  bool _siteTapConsumesMapTap = false;
  Ticker? _rotateOverlayTicker;
  String? _appliedLightPreset;
  MapboxBasemapTheme? _appliedBasemapTheme;
  double? _layoutHeight;
  ui.Size? _viewportSize;
  List<MapRotateVisibleSite> _visibleRotateSites = const [];
  late final MapRotateOverlayController _overlayController;

  late final LatLng _seedCenter;
  late final double _seedZoom;
  late final double _seedHeading;
  /// Stable reference so MapWidget only transitions when we replace it.
  late ViewportState _viewport;

  @override
  void initState() {
    super.initState();
    _overlayController = MapRotateOverlayController(
      onVisibleSitesChanged: (sites) {
        if (!mounted) return;
        final sorted = sortOverlayDepth(sites);
        if (rotateOverlaySitesEqual(_visibleRotateSites, sorted)) return;
        setState(() => _visibleRotateSites = sorted);
        widget.rotateCardCount?.value = sorted.length;
      },
    );
    widget.camera.rotateWithHeading = widget.rotateWithHeading;
    _seedCenter = widget.currentLocation ?? widget.initialCenter;
    _seedZoom = clampMapboxZoom(
      widget.initialZoom < 10 ? MapConfig.mapboxFollowZoom : widget.initialZoom,
    );
    _seedHeading = widget.headingDeg;
    widget.aerialRecon?.addListener(_onAerialReconChanged);
    widget.formationMap?.addListener(_onFormationMapChanged);
    // Seed with a fixed camera; switch to FollowPuck after the location puck
    // is enabled (FollowPuck requires location).
    _viewport = CameraViewportState(
      center: Point(
        coordinates: Position(_seedCenter.longitude, _seedCenter.latitude),
      ),
      zoom: _seedZoom,
      bearing: widget.rotateWithHeading
          ? mapboxBearingFromHeading(_seedHeading)
          : 0,
      pitch: mapboxPitchForMode(rotateWithHeading: widget.rotateWithHeading),
    );
    _readyTimeout = Timer(const Duration(seconds: 15), () {
      if (!mounted || _readyNotified) return;
      if (!_ready) {
        widget.onError?.call(
          'Mapbox did not become ready (token/style). '
          'Confirm ./run.sh uses .dart_defines.json and rebuild.',
        );
        setState(() => _ready = true);
      }
      // Always release splash/UI hold after the timeout.
      _notifyParentReady();
    });
    unawaited(_ensureTokenThenShow());
  }

  /// Camera is seeded; tell the parent once the map has painted (idle) or
  /// after a short fallback so splash does not clear on a blank map.
  void _markInternallyReady() {
    _readyTimeout?.cancel();
    if (!mounted) return;
    setState(() => _ready = true);
    unawaited(_syncAerialMission());
    _readyNotifyFallback?.cancel();
    _readyNotifyFallback = Timer(const Duration(milliseconds: 2500), () {
      _notifyParentReady();
    });
  }

  void _notifyParentReady() {
    if (_readyNotified || !_ready) return;
    _readyNotified = true;
    _readyNotifyFallback?.cancel();
    widget.onReadyChanged(true);
  }

  Future<void> _ensureTokenThenShow() async {
    final token = MapConfig.mapboxAccessToken;
    if (token.isEmpty) {
      widget.onError?.call('MAPBOX_ACCESS_TOKEN missing from build');
      return;
    }
    MapboxOptions.setAccessToken(token);
    for (var i = 0; i < 40; i++) {
      try {
        if (await MapboxOptions.getAccessToken() == token) break;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted) return;
    setState(() => _tokenReady = true);
  }

  @override
  void dispose() {
    widget.aerialRecon?.removeListener(_onAerialReconChanged);
    widget.formationMap?.removeListener(_onFormationMapChanged);
    _annotationDebounce?.cancel();
    _readyTimeout?.cancel();
    _readyNotifyFallback?.cancel();
    _followPuckReassertTimer?.cancel();
    _locationPuckTapTimer?.cancel();
    _rotateOverlayTicker?.dispose();
    _overlayController.dispose();
    widget.camera.detach();
    _annotations?.dispose();
    _annotations = null;
    _aerialReconAnnotations?.dispose();
    _aerialReconAnnotations = null;
    unawaited(_formationOverlay.clear());
    _formationOverlay.dispose();
    if (_readyNotified) {
      widget.onReadyChanged(false);
    }
    super.dispose();
  }

  void _onAerialReconChanged() {
    unawaited(_syncAerialMission());
  }

  void _onFormationMapChanged() {
    unawaited(_syncFormationMap());
  }

  Future<void> _syncFormationMap() async {
    final map = _map;
    final formation = widget.formationMap;
    if (map == null || !_styleLoaded) return;
    if (formation == null || !formation.isActive) {
      _lastFormationSitesRevision = -1;
      await _formationOverlay.clear();
      return;
    }
    final origin = formation.origin ?? widget.currentLocation;
    if (origin == null) {
      await _formationOverlay.clear();
      return;
    }
    final revision = formation.sitesRevision;
    if (revision == _lastFormationSitesRevision) return;
    _lastFormationSitesRevision = revision;

    final samples = <FormationMapSiteSample>[
      for (final site in formation.discoverableSites)
        if (site.latitude != null && site.longitude != null)
          FormationMapSiteSample(
            lat: site.latitude!,
            lon: site.longitude!,
            period: site.effectivePeriod ?? 'cretaceous',
          ),
    ];
    developer.log(
      'Formation map raster sites=${samples.length} '
      'rangeM=${formation.rangeM.toStringAsFixed(0)} '
      'accuracy=${formation.accuracy.toStringAsFixed(2)} '
      'origin=${origin.latitude.toStringAsFixed(5)},'
      '${origin.longitude.toStringAsFixed(5)}',
      name: 'formation_map',
    );
    final cfg = GameConfig.instance.toolActions.formationMap;
    final palette = GameConfig.instance.periodColors.formationMap;
    final request = FormationMapRasterRequest(
      originLat: origin.latitude,
      originLon: origin.longitude,
      rangeM: formation.rangeM,
      accuracy: formation.accuracy,
      sites: samples,
      baseAlpha: cfg.baseAlpha,
      rangeFade: cfg.rangeFade,
      boundaryBlur: cfg.boundaryBlur,
      colors: FormationMapRasterColors(
        cretaceous: palette.cretaceous,
        jurassic: palette.jurassic,
        triassic: palette.triassic,
      ),
    );
    // 128² grid is cheap enough on the UI isolate; avoid compute() because
    // custom request objects are not SendPort-safe.
    final raster = buildFormationMapRaster(request);
    if (!mounted) return;
    if (widget.formationMap?.sitesRevision != revision) return;
    if (!(widget.formationMap?.isActive ?? false)) {
      await _formationOverlay.clear();
      return;
    }
    await _formationOverlay.sync(raster: raster);
  }

  MbxEdgeInsets? _paddingForCurrentHeight() {
    final height = _layoutHeight;
    if (height == null || height <= 0) return null;
    final focusFromBottom = MapConfig.mapboxRotateFocusFromBottom;
    final top = height * (1 - 2 * focusFromBottom);
    return MbxEdgeInsets(
      top: top.clamp(0.0, height),
      left: 0,
      bottom: 0,
      right: 0,
    );
  }

  double get _liveHeadingDeg =>
      widget.headingListenable?.value ?? widget.headingDeg;

  FollowPuckViewportState _followPuckViewport() {
    return FollowPuckViewportState(
      zoom: MapConfig.mapboxRotateZoom,
      pitch: MapConfig.mapboxFollowPitch,
      bearing: const FollowPuckViewportStateBearingHeading(),
      padding: _paddingForCurrentHeight(),
    );
  }

  void _enterFollowPuck({bool animated = true}) {
    unawaited(MapboxViewportNative.disableIdleOnUserInteraction());
    setStateWithViewportAnimation(
      () => _viewport = _followPuckViewport(),
      // null → native immediate transition (used when re-asserting after taps).
      transition: animated
          ? const DefaultViewportTransition(
              maxDuration: Duration(milliseconds: 1200),
            )
          : null,
    );
  }

  void _exitFollowPuck() {
    _followPuckReassertTimer?.cancel();
    // Release FollowPuck immediately so Dart flyTo owns the exit animation.
    // Animating Idle→camera here does nothing useful (Idle has no target) and
    // used to race an instant setCamera — that was the exit snap.
    setStateWithViewportAnimation(
      () => _viewport = const IdleViewportState(),
      transition: null,
    );
    unawaited(
      widget.camera.applyOrientationMode(
        rotateWithHeading: false,
        headingDeg: _liveHeadingDeg,
        zoom: MapConfig.mapboxFollowZoom,
      ),
    );
  }

  /// Belt-and-suspenders: if a tap still cancels FollowPuck, re-engage.
  void _scheduleFollowPuckReassert() {
    if (!widget.rotateWithHeading || !_ready) return;
    unawaited(MapboxViewportNative.disableIdleOnUserInteraction());
    _followPuckReassertTimer?.cancel();
    _followPuckReassertTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || !widget.rotateWithHeading || !_ready) return;
      _enterFollowPuck(animated: false);
    });
  }

  void _onSiteTap(SiteSummary site) {
    // Annotation tap often arrives with/just after map onTap — suppress puck.
    _siteTapConsumesMapTap = true;
    _locationPuckTapTimer?.cancel();
    _locationPuckTapTimer = null;
    widget.onSiteTap(site);
    _scheduleFollowPuckReassert();
  }

  void _onRotateMiniCardTap(SiteSummary site) {
    _onSiteTap(site);
  }

  void _onRotateOverlayTick(Duration elapsed) {
    if (!widget.rotateWithHeading || !widget.mapActive || !_ready) return;
    _syncRotateOverlayFrame();
  }

  void _setRotateOverlayTickerActive(bool active) {
    if (active && widget.mapActive) {
      if (_rotateOverlayTicker == null) {
        _rotateOverlayTicker = createTicker(_onRotateOverlayTick)..start();
      }
      _syncRotateOverlayFrame();
    } else {
      _rotateOverlayTicker?.dispose();
      _rotateOverlayTicker = null;
    }
  }

  Future<void> _applyRotateMarkerMode(bool rotate) async {
    await _annotations?.setRotateModePaused(rotate);
    if (!mounted) return;
    if (rotate && widget.mapActive) {
      _setRotateOverlayTickerActive(true);
      // Keep circle annotations warm under opacity 0 while rotate is on.
      _scheduleAnnotationSync();
    } else {
      _setRotateOverlayTickerActive(false);
      setState(() => _visibleRotateSites = const []);
      widget.rotateCardCount?.value = 0;
      if (!rotate) {
        // Circles should already be painted; light sync + opacity restore.
        _scheduleAnnotationSync();
      }
    }
  }

  void _syncRotateOverlayFrame() {
    if (!widget.rotateWithHeading || !widget.mapActive || !_ready) return;
    final size = _viewportSize;
    final map = _map;
    if (size == null || map == null) return;
    _overlayController.syncFrame(
      map: map,
      sites: widget.sites,
      viewportSize: size,
      cullCenter: widget.currentLocation,
    );
  }

  void _onMapTap(MapContentGestureContext context) {
    if (widget.rotateWithHeading) {
      _scheduleFollowPuckReassert();
      return;
    }
    // Defer so a concurrent site-annotation tap can cancel this.
    _siteTapConsumesMapTap = false;
    _locationPuckTapTimer?.cancel();
    _locationPuckTapTimer = Timer(const Duration(milliseconds: 40), () {
      if (!mounted || _siteTapConsumesMapTap) return;
      unawaited(_maybeHandleLocationPuckTap(context));
    });
  }

  /// Screen hit-test against the location puck (fixed visual size ~32pt).
  Future<void> _maybeHandleLocationPuckTap(
    MapContentGestureContext context,
  ) async {
    final map = _map;
    final location = widget.currentLocation;
    if (map == null ||
        location == null ||
        !widget.mapActive ||
        widget.rotateWithHeading) {
      return;
    }
    try {
      final puckPixel = await map.pixelForCoordinate(
        Point(
          coordinates: Position(location.longitude, location.latitude),
        ),
      );
      final dx = puckPixel.x - context.touchPosition.x;
      final dy = puckPixel.y - context.touchPosition.y;
      const hitRadius = 44.0;
      if (dx * dx + dy * dy <= hitRadius * hitRadius) {
        widget.onLocationPuckTap();
      }
    } catch (_) {}
  }

  void _refreshFollowPuckPadding() {
    if (!widget.rotateWithHeading || !_ready) return;
    if (_viewport is! FollowPuckViewportState) return;
    setStateWithViewportAnimation(
      () => _viewport = _followPuckViewport(),
      transition: const DefaultViewportTransition(
        maxDuration: Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant MapboxFieldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _annotations?.onSiteTap = _onSiteTap;
    if (!_ready) return;

    if (oldWidget.rotateWithHeading != widget.rotateWithHeading) {
      widget.camera.rotateWithHeading = widget.rotateWithHeading;
      unawaited(_applyGestureMode());
      unawaited(_applyRotateMarkerMode(widget.rotateWithHeading));
      if (widget.rotateWithHeading) {
        _enterFollowPuck();
      } else {
        _exitFollowPuck();
      }
      unawaited(_syncAerialMission());
    }

    // North-fixed GPS follow only — rotate mode is owned by FollowPuck.
    // Skip when *exiting* rotate: [applyOrientationMode] already flyTos flat
    // north-up; an instant followLocation setCamera would snap over that.
    final shouldFollow = widget.followUser && !widget.rotateWithHeading;
    final exitingRotate =
        oldWidget.rotateWithHeading && !widget.rotateWithHeading;
    if (shouldFollow &&
        !exitingRotate &&
        widget.currentLocation != null &&
        (oldWidget.currentLocation != widget.currentLocation ||
            oldWidget.followUser != widget.followUser)) {
      unawaited(
        widget.camera.followLocation(
          widget.currentLocation!,
          followUser: true,
        ),
      );
    }
    if (oldWidget.selectedSite?.siteId != widget.selectedSite?.siteId) {
      // Selection must not wait on the site-list debounce — apply immediately.
      if (!widget.rotateWithHeading) {
        unawaited(
          _annotations?.applySelectedSiteId(widget.selectedSite?.siteId),
        );
      }
    }
    if (oldWidget.markerDatasetKey != widget.markerDatasetKey) {
      // Dataset / filter switch: wipe immediately, then paint — no debounce.
      // Keep circles warm under rotate (opacity 0) so north-fixed exit is instant.
      if (widget.rotateWithHeading) {
        _syncRotateOverlayFrame();
      }
      _annotationDebounce?.cancel();
      unawaited(_switchDatasetAndSync());
    } else if (oldWidget.sites != widget.sites) {
      // Same dataset: debounce circle sync; rotate overlay updates immediately.
      if (widget.rotateWithHeading) {
        _syncRotateOverlayFrame();
      }
      _scheduleAnnotationSync();
    }
    // Location cull-center updates; heading is owned by FollowPuck / ticker —
    // do not rebuild-sync on headingDeg (would fight compass decoupling).
    if (widget.rotateWithHeading &&
        oldWidget.currentLocation != widget.currentLocation) {
      _syncRotateOverlayFrame();
    }
    if (oldWidget.mapActive != widget.mapActive ||
        oldWidget.rotateWithHeading != widget.rotateWithHeading) {
      if (widget.rotateWithHeading && widget.mapActive && _ready) {
        _setRotateOverlayTickerActive(true);
      } else {
        _setRotateOverlayTickerActive(false);
      }
    }
    if (oldWidget.basemapTheme != widget.basemapTheme ||
        oldWidget.brightness != widget.brightness) {
      unawaited(_applyBasemapLook(force: true));
    }
    if (oldWidget.avatarImageUrl != widget.avatarImageUrl) {
      unawaited(
        widget.camera.enableLocationPuck(
          avatarImageUrl: widget.avatarImageUrl,
        ),
      );
    }
    if (oldWidget.aerialRecon != widget.aerialRecon) {
      oldWidget.aerialRecon?.removeListener(_onAerialReconChanged);
      widget.aerialRecon?.addListener(_onAerialReconChanged);
      unawaited(_syncAerialMission());
    }
    if (oldWidget.formationMap != widget.formationMap) {
      oldWidget.formationMap?.removeListener(_onFormationMapChanged);
      widget.formationMap?.addListener(_onFormationMapChanged);
      _lastFormationSitesRevision = -1;
      unawaited(_syncFormationMap());
    }
    if (oldWidget.showPastAerialRoutes != widget.showPastAerialRoutes ||
        oldWidget.showAerialReconOverlays != widget.showAerialReconOverlays) {
      unawaited(_syncAerialMission());
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    widget.camera.attach(map);
    widget.camera.rotateWithHeading = widget.rotateWithHeading;
    unawaited(_applyBasemapLook(force: true));
    unawaited(_seedAfterLayout());

    try {
      final shadowManager =
          await map.annotations.createCircleAnnotationManager();
      final manager = await map.annotations.createCircleAnnotationManager();
      final selectionDotManager =
          await map.annotations.createCircleAnnotationManager();
      final annotations = MapboxSiteAnnotations(onSiteTap: _onSiteTap);
      await annotations.attach(
        shadowManager: shadowManager,
        manager: manager,
        selectionDotManager: selectionDotManager,
      );
      _annotations?.dispose();
      _annotations = annotations;

      final lineManager =
          await map.annotations.createPolylineAnnotationManager();
      final scoutManager =
          await map.annotations.createPointAnnotationManager();
      final aerial = MapboxAerialMissionAnnotations();
      await aerial.attach(
        lineManager: lineManager,
        scoutManager: scoutManager,
        onScoutTap: (missionId) {
          final recon = widget.aerialRecon;
          if (recon == null) return;
          for (final mission in recon.missions) {
            if (mission.missionId == missionId) {
              recon.focusMission(mission);
              return;
            }
          }
        },
      );
      _aerialReconAnnotations?.dispose();
      _aerialReconAnnotations = aerial;

      _formationOverlay.attach(map);
      unawaited(_syncFormationMap());

      await _applyGestureMode();
      _scheduleAnnotationSync();
      unawaited(_syncAerialMission());
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('MapboxFieldMap setup failed: $error\n$stack');
      }
    }
  }

  Future<void> _applyGestureMode() async {
    final map = _map;
    if (map == null) return;
    final locked = widget.rotateWithHeading;
    await map.gestures.updateSettings(
      GesturesSettings(
        rotateEnabled: false,
        pitchEnabled: false,
        scrollEnabled: !locked,
        pinchToZoomEnabled: !locked,
        pinchPanEnabled: !locked,
        doubleTapToZoomInEnabled: !locked,
        doubleTouchToZoomOutEnabled: !locked,
        quickZoomEnabled: !locked,
        simultaneousRotateAndPinchToZoomEnabled: false,
      ),
    );
  }

  void _onStyleLoaded(StyleLoadedEventData data) {
    _styleLoaded = true;
    unawaited(_applyBasemapLook());
    unawaited(_seedAfterLayout());
    _lastFormationSitesRevision = -1;
    unawaited(_syncFormationMap());
  }

  void _onMapLoaded(MapLoadedEventData data) {
    _styleLoaded = true;
    unawaited(_applyBasemapLook());
    unawaited(_seedAfterLayout());
    _lastFormationSitesRevision = -1;
    unawaited(_syncFormationMap());
  }

  Future<void> _applyBasemapLook({bool force = false}) async {
    final map = _map;
    if (map == null || !_styleLoaded) return;
    final preset =
        MapboxBasemapConfig.lightPresetForBrightness(widget.brightness);
    final theme = widget.basemapTheme;
    if (!force &&
        preset == _appliedLightPreset &&
        theme == _appliedBasemapTheme) {
      return;
    }
    try {
      await MapboxBasemapConfig.apply(
        map,
        lightPreset: preset,
        theme: theme,
        brightness: widget.brightness,
      );
      _appliedLightPreset = preset;
      _appliedBasemapTheme = theme;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapboxFieldMap basemap config failed: $error');
      }
    }
  }

  Future<void> _seedAfterLayout() async {
    if (_cameraSeeded || _seeding || _map == null || !_styleLoaded) return;
    _seeding = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || _map == null || _cameraSeeded) return;

      // FollowPuck needs the location component; enable before entering it.
      try {
        await widget.camera.enableLocationPuck(
          avatarImageUrl: widget.avatarImageUrl,
        );
      } catch (_) {}

      if (widget.rotateWithHeading) {
        _enterFollowPuck();
      } else {
        await widget.camera.seedCamera(
          center: widget.currentLocation ?? _seedCenter,
          zoom: _seedZoom,
          headingDeg: _liveHeadingDeg,
        );
      }

      _cameraSeeded = true;
      if (!mounted) return;
      _markInternallyReady();
      unawaited(_applyRotateMarkerMode(widget.rotateWithHeading));
      if (widget.rotateWithHeading) {
        _setRotateOverlayTickerActive(true);
      } else {
        _scheduleAnnotationSync();
      }
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('MapboxFieldMap seed failed: $error\n$stack');
      }
      widget.onError?.call(error);
    } finally {
      _seeding = false;
    }
  }

  void _scheduleAnnotationSync() {
    _annotationDebounce?.cancel();
    _annotationDebounce = Timer(const Duration(milliseconds: 80), () {
      unawaited(_syncAnnotations());
    });
  }

  /// Wipe markers as soon as the dataset key changes, then fill from cache.
  Future<void> _switchDatasetAndSync() async {
    final annotations = _annotations;
    if (annotations == null || !_ready) return;
    try {
      final key = widget.markerDatasetKey;
      await annotations.beginDatasetSwitch(key);
      if (!mounted) return;
      // A newer switch won; that call will sync.
      if (widget.markerDatasetKey != key) return;
      await _syncAnnotations();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapboxFieldMap dataset switch failed: $error');
      }
    }
  }

  Future<void> _syncAnnotations() async {
    final map = _map;
    final annotations = _annotations;
    if (map == null || annotations == null || !_ready) return;
    try {
      await annotations.sync(
        map: map,
        sites: widget.sites,
        selectedSite: widget.selectedSite,
        datasetKey: widget.markerDatasetKey,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapboxFieldMap annotation sync failed: $error');
      }
    }
  }

  Future<void> _syncAerialMission() async {
    final aerial = _aerialReconAnnotations;
    final controller = widget.aerialRecon;
    if (aerial == null || !_ready) return;
    try {
      // Keep rotate mode uncluttered — no scout loops/pucks over FollowPuck.
      // Archive mode never shows recon overlays.
      if (widget.rotateWithHeading ||
          controller == null ||
          !widget.showAerialReconOverlays) {
        await aerial.clear();
        return;
      }
      await aerial.sync(
        controller,
        showPastAerialRoutes: widget.showPastAerialRoutes,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MapboxFieldMap aerial recon sync failed: $error');
      }
    }
  }

  void _onScroll(MapContentGestureContext context) {
    if (widget.rotateWithHeading) return;
    if (context.gestureState == GestureState.started ||
        context.gestureState == GestureState.changed) {
      widget.onFollowCancelled();
    }
  }

  void _onCameraChange(CameraChangedEventData data) {
    if (!_ready || !widget.mapActive) return;
    if (widget.rotateWithHeading) {
      // Rotate mini-cards are driven by the vsync ticker only. Syncing here
      // too queued stale projections and made cards jitter behind FollowPuck.
      return;
    }
    widget.onZoomChanged(data.cameraState.zoom);
    // Update marker size immediately while zooming (no debounce / bucket wait).
    final annotations = _annotations;
    if (annotations != null) {
      unawaited(annotations.applyZoomRadius(data.cameraState.zoom));
    }
  }

  void _onMapIdle(MapIdleEventData data) {
    // First idle after camera seed ≈ tiles painted; release splash hold.
    if (_ready) _notifyParentReady();
    widget.onMapIdle?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_tokenReady) {
      return const ColoredBox(
        color: Color(0xFFE8DFD4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 12),
              Text('Preparing Mapbox…'),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        if (height.isFinite && height > 0 && width.isFinite && width > 0) {
          widget.camera.setViewportSize(width: width, height: height);
          final previous = _layoutHeight;
          final size = ui.Size(width, height);
          final sizeChanged = _viewportSize != size;
          if (sizeChanged) {
            _viewportSize = size;
          }
          if (previous != height) {
            _layoutHeight = height;
            if (previous != null && (previous - height).abs() >= 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _refreshFollowPuckPadding();
              });
            }
          }
          if (sizeChanged && widget.rotateWithHeading && _ready) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _syncRotateOverlayFrame();
            });
          }
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            MapWidget(
              key: const ValueKey('mapbox_field_map'),
              styleUri: MapboxStyles.STANDARD,
              viewport: _viewport,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              onMapLoadedListener: _onMapLoaded,
              onTapListener: _onMapTap,
              onScrollListener: _onScroll,
              onCameraChangeListener: _onCameraChange,
              onMapIdleListener: _onMapIdle,
              onMapLoadErrorListener: (event) {
                widget.onError?.call(event.message);
              },
            ),
            // Mode 1 only (north-fixed, not following). Hidden while centered.
            if (!widget.rotateWithHeading && !widget.followUser && _ready)
              const MapCenterCrosshair(),
            if (widget.rotateWithHeading && _ready)
              Positioned.fill(
                child: MapRotateSiteCardOverlay(
                  visibleSites: _visibleRotateSites,
                  selectedSiteId: widget.selectedSite?.siteId,
                  hiddenSiteId: widget.hiddenRotateSiteId,
                  onSiteTap: _onRotateMiniCardTap,
                ),
              ),
            // Translucent so mini-card taps still work; detects pinch-out to
            // leave rotate mode (FollowPuck locks Mapbox pinch gestures).
            if (widget.rotateWithHeading && _ready)
              Positioned.fill(
                child: _RotatePinchZoomOutListener(
                  onZoomOut: widget.onRotatePinchZoomOut,
                ),
              ),
            if (!_ready)
              Positioned(
                left: 16,
                right: 16,
                bottom: 160,
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.95),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Expanded(child: Text('Loading map tiles…')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Two-finger pinch-out detector for rotate mode.
///
/// Uses a translucent [Listener] so mini-card taps still reach the overlay
/// below. Mapbox pinch is locked while FollowPuck owns the camera.
class _RotatePinchZoomOutListener extends StatefulWidget {
  const _RotatePinchZoomOutListener({required this.onZoomOut});

  final VoidCallback onZoomOut;

  /// Fingers must close to this fraction of the start span to count as zoom-out.
  static const double zoomOutSpanRatio = 0.88;

  @override
  State<_RotatePinchZoomOutListener> createState() =>
      _RotatePinchZoomOutListenerState();
}

class _RotatePinchZoomOutListenerState
    extends State<_RotatePinchZoomOutListener> {
  final Map<int, Offset> _pointers = {};
  double? _startSpan;
  bool _fired = false;

  double? _currentSpan() {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _startSpan = _currentSpan();
      _fired = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final start = _startSpan;
    final now = _currentSpan();
    if (_fired || start == null || now == null || start <= 0) return;
    if (now / start <= _RotatePinchZoomOutListener.zoomOutSpanRatio) {
      _fired = true;
      widget.onZoomOut();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _startSpan = null;
      _fired = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: const SizedBox.expand(),
    );
  }
}
