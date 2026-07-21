import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../models/site.dart';
import 'mapbox_basemap_config.dart';
import 'mapbox_camera_coordinator.dart';
import 'mapbox_site_annotations.dart';

/// Mapbox Standard field map — warm theme, time-of-day lighting, site markers.
///
/// [rotateWithHeading] false = north-fixed; true = map bearing follows phone.
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
    required this.onSiteTap,
    required this.onFollowCancelled,
    required this.onZoomChanged,
    required this.onReadyChanged,
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
  final ValueChanged<SiteSummary> onSiteTap;
  final VoidCallback onFollowCancelled;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<bool> onReadyChanged;
  final ValueChanged<Object>? onError;

  @override
  State<MapboxFieldMap> createState() => _MapboxFieldMapState();
}

class _MapboxFieldMapState extends State<MapboxFieldMap> {
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
  String? _appliedLightPreset;

  late final LatLng _seedCenter;
  late final double _seedZoom;
  late final double _seedHeading;
  late final CameraViewportState _initialViewport;

  @override
  void initState() {
    super.initState();
    widget.camera.rotateWithHeading = widget.rotateWithHeading;
    _seedCenter = widget.currentLocation ?? widget.initialCenter;
    _seedZoom = clampMapboxZoom(
      widget.initialZoom < 10 ? MapConfig.mapboxFollowZoom : widget.initialZoom,
    );
    _seedHeading = widget.headingDeg;
    _initialViewport = CameraViewportState(
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
    widget.camera.detach();
    _annotations?.dispose();
    _annotations = null;
    if (_ready) {
      widget.onReadyChanged(false);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapboxFieldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _annotations?.onSiteTap = widget.onSiteTap;
    if (!_ready) return;

    if (oldWidget.rotateWithHeading != widget.rotateWithHeading) {
      unawaited(_applyGestureMode());
      unawaited(
        widget.camera.applyOrientationMode(
          rotateWithHeading: widget.rotateWithHeading,
          headingDeg: widget.headingDeg,
          zoom: widget.rotateWithHeading ? MapConfig.mapboxRotateZoom : null,
        ),
      );
      if (widget.rotateWithHeading && widget.currentLocation != null) {
        unawaited(
          widget.camera.centerOn(
            widget.currentLocation!,
            zoom: MapConfig.mapboxRotateZoom,
            headingDeg: widget.headingDeg,
          ),
        );
      }
    } else if (widget.rotateWithHeading &&
        oldWidget.headingDeg != widget.headingDeg) {
      unawaited(widget.camera.applyHeading(widget.headingDeg));
    }

    final shouldFollow = widget.followUser || widget.rotateWithHeading;
    if (shouldFollow &&
        widget.currentLocation != null &&
        (oldWidget.currentLocation != widget.currentLocation ||
            oldWidget.followUser != widget.followUser ||
            oldWidget.rotateWithHeading != widget.rotateWithHeading)) {
      unawaited(
        widget.camera.followLocation(
          widget.currentLocation!,
          followUser: true,
          zoom: widget.rotateWithHeading ? MapConfig.mapboxRotateZoom : null,
        ),
      );
    }
    if (oldWidget.selectedSite?.siteId != widget.selectedSite?.siteId) {
      // Selection must not wait on the site-list debounce — apply immediately.
      unawaited(
        _annotations?.applySelectedSiteId(widget.selectedSite?.siteId),
      );
    }
    if (oldWidget.sites != widget.sites ||
        oldWidget.markerDatasetKey != widget.markerDatasetKey) {
      _scheduleAnnotationSync();
    }
    if (oldWidget.currentLocation != widget.currentLocation) {
      unawaited(_applyBasemapLook());
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
      final annotations = MapboxSiteAnnotations(onSiteTap: widget.onSiteTap);
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
    if (!force && preset == _appliedLightPreset) return;
    try {
      await MapboxBasemapConfig.apply(
        map,
        lightPreset: preset,
        latitude: loc.latitude,
        longitude: loc.longitude,
      );
      _appliedLightPreset = preset;
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

      await widget.camera.seedCamera(
        center: widget.currentLocation ?? _seedCenter,
        zoom: _seedZoom,
        headingDeg: widget.headingDeg,
      );
      try {
        await widget.camera.enableLocationPuck();
      } catch (_) {}

      _cameraSeeded = true;
      _readyTimeout?.cancel();
      if (!mounted) return;
      setState(() => _ready = true);
      widget.onReadyChanged(true);
      _scheduleAnnotationSync();
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
    if (!widget.rotateWithHeading) {
      widget.onZoomChanged(data.cameraState.zoom);
    }
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
        if (height.isFinite && height > 0) {
          widget.camera.setViewportHeight(height);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            MapWidget(
              key: const ValueKey('mapbox_field_map'),
              styleUri: MapboxStyles.STANDARD,
              viewport: _initialViewport,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              onMapLoadedListener: _onMapLoaded,
              onScrollListener: _onScroll,
              onCameraChangeListener: _onCameraChange,
              onMapIdleListener: _onMapIdle,
              onMapLoadErrorListener: (event) {
                widget.onError?.call(event.message);
              },
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
