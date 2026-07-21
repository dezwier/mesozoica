import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../models/site.dart';
import 'mapbox_basemap_config.dart';
import 'mapbox_camera_coordinator.dart';
import 'mapbox_site_annotations.dart';
import 'mapbox_viewport_native.dart';
import 'map_rotate_site_card_overlay.dart';

typedef MapSiteTapCallback = void Function(SiteSummary site);

/// Mapbox Standard field map — warm theme, time-of-day lighting, site markers.
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
    required this.onSiteTap,
    required this.onFollowCancelled,
    required this.onZoomChanged,
    required this.onReadyChanged,
    this.hiddenRotateSiteId,
    this.onError,
  });

  final MapboxCameraCoordinator camera;
  final bool rotateWithHeading;
  final List<SiteSummary> sites;
  final SiteSummary? selectedSite;
  /// Changes on archive ↔ field ↔ show-all (and filters) → wipe + reload.
  final String markerDatasetKey;
  final LatLng? currentLocation;
  final double headingDeg;
  final bool followUser;
  final LatLng initialCenter;
  final double initialZoom;
  final MapboxBasemapTheme basemapTheme;
  final MapSiteTapCallback onSiteTap;
  final VoidCallback onFollowCancelled;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<bool> onReadyChanged;
  /// Hide this site's mini-card while the detail sheet morphs open.
  final int? hiddenRotateSiteId;
  final ValueChanged<Object>? onError;

  @override
  State<MapboxFieldMap> createState() => _MapboxFieldMapState();
}

class _MapboxFieldMapState extends State<MapboxFieldMap>
    with SingleTickerProviderStateMixin {
  MapboxSiteAnnotations? _annotations;
  MapboxMap? _map;
  bool _ready = false;
  bool _styleLoaded = false;
  bool _cameraSeeded = false;
  bool _seeding = false;
  bool _tokenReady = false;
  Timer? _annotationDebounce;
  Timer? _readyTimeout;
  Timer? _lightPresetTimer;
  Timer? _followPuckReassertTimer;
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
      },
    );
    widget.camera.rotateWithHeading = widget.rotateWithHeading;
    _seedCenter = widget.currentLocation ?? widget.initialCenter;
    _seedZoom = clampMapboxZoom(
      widget.initialZoom < 10 ? MapConfig.mapboxFollowZoom : widget.initialZoom,
    );
    _seedHeading = widget.headingDeg;
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
      if (!mounted || _ready) return;
      widget.onError?.call(
        'Mapbox did not become ready (token/style). '
        'Confirm ./run.sh uses .dart_defines.json and rebuild.',
      );
    });
    unawaited(_ensureTokenThenShow());
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
    _annotationDebounce?.cancel();
    _readyTimeout?.cancel();
    _lightPresetTimer?.cancel();
    _followPuckReassertTimer?.cancel();
    _rotateOverlayTicker?.dispose();
    _overlayController.dispose();
    widget.camera.detach();
    _annotations?.dispose();
    _annotations = null;
    if (_ready) {
      widget.onReadyChanged(false);
    }
    super.dispose();
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
    setStateWithViewportAnimation(
      () => _viewport = const IdleViewportState(),
      transition: const DefaultViewportTransition(
        maxDuration: Duration(milliseconds: 800),
      ),
    );
    unawaited(
      widget.camera.applyOrientationMode(
        rotateWithHeading: false,
        headingDeg: widget.headingDeg,
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
    widget.onSiteTap(site);
    _scheduleFollowPuckReassert();
  }

  void _onRotateMiniCardTap(SiteSummary site) {
    _onSiteTap(site);
  }

  void _onRotateOverlayTick(Duration elapsed) {
    if (!widget.rotateWithHeading || !_ready) return;
    _syncRotateOverlayFrame();
  }

  void _setRotateOverlayTickerActive(bool active) {
    if (active) {
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
    if (rotate) {
      _setRotateOverlayTickerActive(true);
    } else {
      _setRotateOverlayTickerActive(false);
      setState(() => _visibleRotateSites = const []);
      _scheduleAnnotationSync();
    }
  }

  void _syncRotateOverlayFrame() {
    if (!widget.rotateWithHeading || !_ready) return;
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
    _scheduleFollowPuckReassert();
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
    }

    // North-fixed GPS follow only — rotate mode is owned by FollowPuck.
    final shouldFollow = widget.followUser && !widget.rotateWithHeading;
    if (shouldFollow &&
        widget.currentLocation != null &&
        (oldWidget.currentLocation != widget.currentLocation ||
            oldWidget.followUser != widget.followUser ||
            oldWidget.rotateWithHeading != widget.rotateWithHeading)) {
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
    if (oldWidget.sites != widget.sites ||
        oldWidget.markerDatasetKey != widget.markerDatasetKey) {
      if (widget.rotateWithHeading) {
        _syncRotateOverlayFrame();
      } else {
        _scheduleAnnotationSync();
      }
    }
    if (widget.rotateWithHeading &&
        (oldWidget.sites != widget.sites ||
            oldWidget.markerDatasetKey != widget.markerDatasetKey ||
            oldWidget.currentLocation != widget.currentLocation ||
            oldWidget.headingDeg != widget.headingDeg)) {
      _syncRotateOverlayFrame();
    }
    if (oldWidget.currentLocation != widget.currentLocation) {
      unawaited(_applyBasemapLook());
    }
    if (oldWidget.basemapTheme != widget.basemapTheme) {
      unawaited(_applyBasemapLook(force: true));
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
      await _applyGestureMode();
      _scheduleAnnotationSync();
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
  }

  void _onMapLoaded(MapLoadedEventData data) {
    _styleLoaded = true;
    unawaited(_applyBasemapLook());
    unawaited(_seedAfterLayout());
  }

  LatLng get _lightPresetLocation =>
      widget.currentLocation ?? _seedCenter;

  Future<void> _applyBasemapLook({bool force = false}) async {
    final map = _map;
    if (map == null || !_styleLoaded) return;
    final loc = _lightPresetLocation;
    final preset = MapboxBasemapConfig.lightPresetForDateTime(
      DateTime.now(),
      latitude: loc.latitude,
      longitude: loc.longitude,
    );
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
        latitude: loc.latitude,
        longitude: loc.longitude,
      );
      _appliedLightPreset = preset;
      _appliedBasemapTheme = theme;
      _lightPresetTimer ??= Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_applyBasemapLook()),
      );
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
        await widget.camera.enableLocationPuck();
      } catch (_) {}

      if (widget.rotateWithHeading) {
        _enterFollowPuck();
      } else {
        await widget.camera.seedCamera(
          center: widget.currentLocation ?? _seedCenter,
          zoom: _seedZoom,
          headingDeg: widget.headingDeg,
        );
      }

      _cameraSeeded = true;
      _readyTimeout?.cancel();
      if (!mounted) return;
      setState(() => _ready = true);
      widget.onReadyChanged(true);
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

  Future<void> _syncAnnotations() async {
    final map = _map;
    final annotations = _annotations;
    if (map == null || annotations == null || !_ready) return;
    if (widget.rotateWithHeading || annotations.rotateModePaused) return;
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

  void _onScroll(MapContentGestureContext context) {
    if (widget.rotateWithHeading) return;
    if (context.gestureState == GestureState.started ||
        context.gestureState == GestureState.changed) {
      widget.onFollowCancelled();
    }
  }

  void _onCameraChange(CameraChangedEventData data) {
    if (!_ready) return;
    if (widget.rotateWithHeading) {
      _syncRotateOverlayFrame();
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
    // Markers are not viewport-culled; idle sync is unnecessary.
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
          widget.camera.setViewportHeight(height);
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
            if (widget.rotateWithHeading && _ready)
              Positioned.fill(
                child: MapRotateSiteCardOverlay(
                  visibleSites: _visibleRotateSites,
                  selectedSiteId: widget.selectedSite?.siteId,
                  hiddenSiteId: widget.hiddenRotateSiteId,
                  onSiteTap: _onRotateMiniCardTap,
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
