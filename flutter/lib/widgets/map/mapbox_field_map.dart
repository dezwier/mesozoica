import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../config/game_config.dart';
import '../../config/main_param_resolve.dart';
import '../../controllers/aerial_session_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/formation_map_controller.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../controllers/orbit_survey_controller.dart';
import '../../controllers/ridge_glass_controller.dart';
import '../../controllers/terrain_echo_controller.dart';
import '../../controllers/tool_catalog_controller.dart';
import '../../controllers/weather_controller.dart';
import '../../models/guidance_tool_kind.dart';
import '../../models/ridge_glass_kind.dart';
import '../../models/site.dart';
import '../../models/tool.dart';
import '../../theme/map_chrome_theme.dart';
import 'formation_map_raster.dart';
import 'orbit_survey_raster.dart';
import 'mapbox_aerial_annotations.dart';
import 'mapbox_basemap_config.dart';
import 'mapbox_camera_coordinator.dart';
import 'mapbox_formation_map_overlay.dart';
import 'mapbox_orbit_survey_overlay.dart';
import 'mapbox_site_annotations.dart';
import 'mapbox_viewport_native.dart';
import 'map_center_crosshair.dart';
import 'map_rotate_site_card_overlay.dart';
import 'ridge_glass_pulse_overlay.dart';
import 'terrain_echo_overlay.dart';

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
    this.rotateCardCount,
    this.headingListenable,
    this.locationListenable,
    this.aerialRecon,
    this.orbitSurvey,
    this.formationMap,
    this.showPastAerialRoutes = true,
    this.showAerialReconOverlays = true,
    this.onError,
    this.onMapIdle,
  });

  final MapboxCameraCoordinator camera;
  final bool rotateWithHeading;
  /// When false (catalog/profile/tools open), freeze Mapbox work: pause
  /// FollowPuck / location puck, hide markers, and skip rotate overlay ticks.
  final bool mapActive;
  final List<SiteSummary> sites;
  final SiteSummary? selectedSite;
  /// Changes on archive ↔ field ↔ show-all (and filters) → wipe + reload.
  final String markerDatasetKey;
  final LatLng? currentLocation;
  final double headingDeg;
  /// Live heading without rebuilding this widget (compass decoupled).
  final ValueListenable<double>? headingListenable;
  /// Live GPS without rebuilding the parent MapScreen tree.
  final ValueListenable<LatLng?>? locationListenable;
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
  /// Optional admin HUD counter for visible rotate mini-cards.
  final ValueNotifier<int>? rotateCardCount;
  /// Ongoing + past aerial recon routes / scout puck.
  final AerialSessionController? aerialRecon;
  /// Timed Orbit Survey period mosaic.
  final OrbitSurveyController? orbitSurvey;
  /// Timed Formation Map rock-type square mosaic.
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
  MapboxAerialAnnotations? _aerialReconAnnotations;
  final MapboxOrbitSurveyOverlay _orbitSurveyOverlay = MapboxOrbitSurveyOverlay();
  final MapboxFormationMapOverlay _formationMapOverlay = MapboxFormationMapOverlay();
  MapboxMap? _map;
  int _lastOrbitSurveySitesRevision = -1;
  int _lastFormationMapSitesRevision = -1;
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
  /// North-fixed photo pins when zoomed in (hybrid with Mapbox dots).
  bool _detailPinsActive = false;
  double _lastKnownZoom = MapConfig.mapboxFollowZoom;

  late final LatLng _seedCenter;
  late final double _seedZoom;
  late final double _seedHeading;
  /// Stable reference so MapWidget only transitions when we replace it.
  late ViewportState _viewport;
  /// Latest GPS from [locationListenable] without parent rebuilds.
  LatLng? _liveLocation;
  AuthController? _auth;
  ToolCatalogController? _toolCatalog;
  GuidanceSessionController? _guidance;
  RidgeGlassController? _ridgeGlass;
  WeatherController? _weather;
  VoidCallback? _visibilityListener;

  LatLng? get _effectiveLocation =>
      _liveLocation ?? widget.currentLocation;

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
    _liveLocation = widget.locationListenable?.value ?? widget.currentLocation;
    _seedCenter = _liveLocation ?? widget.initialCenter;
    _seedZoom = clampMapboxZoom(
      widget.initialZoom < 10 ? MapConfig.mapboxFollowZoom : widget.initialZoom,
    );
    _seedHeading = widget.headingDeg;
    widget.locationListenable?.addListener(_onLocationListenable);
    widget.aerialRecon?.addListener(_onAerialReconChanged);
    widget.aerialRecon?.progressTickListenable
        .addListener(_onAerialProgressTick);
    widget.orbitSurvey?.addListener(_onOrbitSurveyChanged);
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
    unawaited(_syncToolSession());
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindVisibilitySources();
  }

  void _bindVisibilitySources() {
    AuthController? auth;
    ToolCatalogController? tools;
    GuidanceSessionController? guidance;
    RidgeGlassController? ridgeGlass;
    WeatherController? weather;
    try {
      auth = context.read<AuthController>();
      tools = context.read<ToolCatalogController>();
      guidance = context.read<GuidanceSessionController>();
      ridgeGlass = context.read<RidgeGlassController>();
      weather = context.read<WeatherController>();
    } on ProviderNotFoundException {
      return;
    }

    _visibilityListener ??= _onVisibilityInputsChanged;
    if (!identical(_auth, auth)) {
      _auth?.removeListener(_visibilityListener!);
      _auth = auth;
      _auth?.addListener(_visibilityListener!);
    }
    if (!identical(_toolCatalog, tools)) {
      _toolCatalog?.removeListener(_visibilityListener!);
      _toolCatalog = tools;
      _toolCatalog?.addListener(_visibilityListener!);
    }
    if (!identical(_guidance, guidance)) {
      _guidance?.removeListener(_visibilityListener!);
      _guidance = guidance;
      _guidance?.addListener(_visibilityListener!);
    }
    if (!identical(_ridgeGlass, ridgeGlass)) {
      _ridgeGlass?.removeListener(_visibilityListener!);
      _ridgeGlass = ridgeGlass;
      _ridgeGlass?.addListener(_visibilityListener!);
    }
    if (!identical(_weather, weather)) {
      _weather?.removeListener(_visibilityListener!);
      _weather = weather;
      _weather?.addListener(_visibilityListener!);
    }
    _syncDiscoveryPulse();
  }

  void _onVisibilityInputsChanged() {
    _syncDiscoveryPulse();
  }

  ({int skillLevel, Set<String> owned, String? activeKey}) _visibilityInputs() {
    var skillLevel = 1;
    final profile = _auth?.currentUser;
    if (profile != null) {
      for (final skill in profile.skills) {
        if (skill.id == 'site_discovery') {
          skillLevel = skill.level.clamp(1, 99);
          break;
        }
      }
    }

    final owned = <String>{};
    final catalog = _toolCatalog;
    if (catalog != null) {
      for (final tool in catalog.items) {
        if (!_toolIsOwned(tool)) continue;
        final kind = GuidanceToolKind.tryParseToolName(tool.name);
        if (kind != null) owned.add(kind.actionKey);
        if (RidgeGlassKind.matchesToolName(tool.name)) {
          owned.add(RidgeGlassKind.actionKey);
        }
      }
    }

    String? activeKey;
    final ridge = _ridgeGlass;
    if (ridge != null && ridge.isActive) {
      activeKey = ridge.session?.actionKey ?? RidgeGlassKind.actionKey;
    } else {
      final guidance = _guidance;
      if (guidance != null && guidance.isActive) {
        activeKey = guidance.kind?.actionKey ?? guidance.session?.actionKey;
      }
    }
    return (skillLevel: skillLevel, owned: owned, activeKey: activeKey);
  }

  double _resolveVisibilityDistanceM({bool ignoreActiveTool = false}) {
    final inputs = _visibilityInputs();
    return resolveSiteDiscoveryVisibilityDistanceM(
      skillLevel: inputs.skillLevel,
      weatherTime: _weather?.weatherTime,
      weatherType: _weather?.status?.weatherType,
      ownedActionKeys: inputs.owned,
      activeActionKey: ignoreActiveTool ? null : inputs.activeKey,
    );
  }

  bool get _ridgeGlassPulseActive {
    final ridge = _ridgeGlass;
    return ridge != null && ridge.isActive;
  }

  static bool _toolIsOwned(ToolSummary tool) =>
      tool.isOwned || tool.ownedOccurrences.isNotEmpty;

  void _syncDiscoveryPulse() {
    if (!mounted || !_ready || !widget.mapActive) return;
    final fullM = _resolveVisibilityDistanceM();
    // Brown native pulse stays at baseline; gold overlay covers the bonus band.
    final pulseM = _ridgeGlassPulseActive
        ? _resolveVisibilityDistanceM(ignoreActiveTool: true)
        : fullM;
    try {
      context.read<FieldDiscoveryCoordinator>().setDiscoverRadiusM(fullM);
    } on ProviderNotFoundException {
      // Tests / previews without discovery coordinator.
    }
    final loc = _effectiveLocation ?? widget.initialCenter;
    final ridgePulse = _ridgeGlassPulseActive;
    unawaited(
      widget.camera.syncLocationPuckPulse(
        // While Ridge Glass draws both rings itself, keep the native pulse off
        // so timing stays locked to the overlay animation.
        visibilityDistanceM: ridgePulse ? fullM : pulseM,
        center: loc,
        zoom: _lastKnownZoom,
        pulseColor: locationPuckPulseBrown,
        pulsingEnabled: !ridgePulse,
      ),
    );
    if (ridgePulse && mounted) setState(() {});
  }

  Future<void> _enableLocationPuck() async {
    final fullM = _resolveVisibilityDistanceM();
    final pulseM = _ridgeGlassPulseActive
        ? _resolveVisibilityDistanceM(ignoreActiveTool: true)
        : fullM;
    final ridgePulse = _ridgeGlassPulseActive;
    try {
      context.read<FieldDiscoveryCoordinator>().setDiscoverRadiusM(fullM);
    } on ProviderNotFoundException {
      // Tests / previews without discovery coordinator.
    }
    final loc = _effectiveLocation ?? widget.initialCenter;
    await widget.camera.enableLocationPuck(
      avatarImageUrl: widget.avatarImageUrl,
      visibilityDistanceM: ridgePulse ? fullM : pulseM,
      center: loc,
      zoom: _lastKnownZoom,
      pulseColor: locationPuckPulseBrown,
      pulsingEnabled: !ridgePulse,
    );
    if (ridgePulse && mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_visibilityListener != null) {
      _auth?.removeListener(_visibilityListener!);
      _toolCatalog?.removeListener(_visibilityListener!);
      _guidance?.removeListener(_visibilityListener!);
      _ridgeGlass?.removeListener(_visibilityListener!);
      _weather?.removeListener(_visibilityListener!);
    }
    widget.locationListenable?.removeListener(_onLocationListenable);
    widget.aerialRecon?.removeListener(_onAerialReconChanged);
    widget.aerialRecon?.progressTickListenable
        .removeListener(_onAerialProgressTick);
    widget.orbitSurvey?.removeListener(_onOrbitSurveyChanged);
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
    unawaited(_orbitSurveyOverlay.clear());
    _orbitSurveyOverlay.dispose();
    unawaited(_formationMapOverlay.clear());
    _formationMapOverlay.dispose();
    if (_readyNotified) {
      widget.onReadyChanged(false);
    }
    super.dispose();
  }

  void _onLocationListenable() {
    if (!mounted) return;
    final loc = widget.locationListenable?.value;
    final prev = _liveLocation;
    if (prev != null &&
        loc != null &&
        prev.latitude == loc.latitude &&
        prev.longitude == loc.longitude) {
      return;
    }
    if (prev == null && loc == null) return;
    _liveLocation = loc;
    final shouldFollow = widget.followUser && !widget.rotateWithHeading;
    if (shouldFollow && loc != null) {
      unawaited(
        widget.camera.followLocation(
          loc,
          followUser: true,
        ),
      );
    }
    if (widget.rotateWithHeading && loc != null) {
      _syncRotateOverlayFrame();
    } else if (_detailPinsActive && loc != null) {
      _syncRotateOverlayFrame();
    }
    if (loc != null) {
      _syncDiscoveryPulse();
    }
  }

  void _onAerialReconChanged() {
    unawaited(_syncToolSession());
  }

  void _onAerialProgressTick() {
    unawaited(_syncToolSession());
  }

  void _onOrbitSurveyChanged() {
    unawaited(_syncOrbitSurvey());
  }

  Future<void> _syncOrbitSurvey() async {
    final map = _map;
    final formation = widget.orbitSurvey;
    if (map == null || !_styleLoaded) return;
    if (!widget.mapActive || formation == null || !formation.isActive) {
      _lastOrbitSurveySitesRevision = -1;
      await _orbitSurveyOverlay.clear();
      return;
    }
    final origin = formation.origin ?? _effectiveLocation;
    if (origin == null) {
      await _orbitSurveyOverlay.clear();
      return;
    }
    final revision = formation.sitesRevision;
    if (revision == _lastOrbitSurveySitesRevision) return;
    _lastOrbitSurveySitesRevision = revision;

    final samples = <OrbitSurveySiteSample>[
      for (final site in formation.discoverableSites)
        if (site.latitude != null && site.longitude != null)
          OrbitSurveySiteSample(
            lat: site.latitude!,
            lon: site.longitude!,
            period: site.effectivePeriod ?? 'cretaceous',
          ),
    ];
    developer.log(
      'Orbit survey raster sites=${samples.length} '
      'rangeM=${formation.rangeM.toStringAsFixed(0)} '
      'accuracy=${formation.accuracy.toStringAsFixed(2)} '
      'origin=${origin.latitude.toStringAsFixed(5)},'
      '${origin.longitude.toStringAsFixed(5)}',
      name: 'orbit_survey',
    );
    final cfg = GameConfig.instance.toolActions.orbitSurvey;
    final palette = GameConfig.instance.periodColors.orbitSurvey;
    final request = OrbitSurveyRasterRequest(
      originLat: origin.latitude,
      originLon: origin.longitude,
      rangeM: formation.rangeM,
      accuracy: formation.accuracy,
      sites: samples,
      baseAlpha: cfg.baseAlpha,
      rangeFade: cfg.rangeFade,
      boundaryBlur: cfg.boundaryBlur,
      colors: OrbitSurveyRasterColors(
        cretaceous: palette.cretaceous,
        jurassic: palette.jurassic,
        triassic: palette.triassic,
      ),
    );
    // IDW + PNG on a worker isolate so walking with Orbit Survey active
    // does not spike the UI isolate (custom request → SendPort-safe map).
    final isolateResult = await compute(
      buildOrbitSurveyPngIsolate,
      request.toIsolatePayload(),
    );
    if (!mounted) return;
    if (widget.orbitSurvey?.sitesRevision != revision) return;
    if (!(widget.orbitSurvey?.isActive ?? false)) {
      await _orbitSurveyOverlay.clear();
      return;
    }
    final raster = orbitSurveyResultFromIsolate(isolateResult);
    await _orbitSurveyOverlay.sync(raster: raster);
  }


  void _onFormationMapChanged() {
    unawaited(_syncFormationMap());
  }

  Future<void> _syncFormationMap() async {
    final map = _map;
    final formation = widget.formationMap;
    if (map == null || !_styleLoaded) return;
    if (!widget.mapActive || formation == null || !formation.isActive) {
      _lastFormationMapSitesRevision = -1;
      await _formationMapOverlay.clear();
      return;
    }
    final footprint = formation.footprint;
    if (footprint == null) {
      await _formationMapOverlay.clear();
      return;
    }
    final revision = formation.sitesRevision;
    if (revision == _lastFormationMapSitesRevision) return;
    _lastFormationMapSitesRevision = revision;

    final samples = <FormationMapSiteSample>[
      for (final site in formation.discoverableSites)
        if (site.latitude != null && site.longitude != null)
          FormationMapSiteSample(
            lat: site.latitude!,
            lon: site.longitude!,
            rockType: (site.rockType ?? site.siteTypeRockType ?? 'other'),
          ),
    ];
    final cfg = GameConfig.instance.toolActions.formationMap;
    final palette = GameConfig.instance.rockTypeColors.formationMap;
    final request = FormationMapRasterRequest(
      west: footprint.west,
      east: footprint.east,
      south: footprint.south,
      north: footprint.north,
      accuracy: formation.accuracy,
      sites: samples,
      baseAlpha: cfg.baseAlpha,
      boundaryBlur: cfg.boundaryBlur,
      colors: palette,
    );
    final isolateResult = await compute(
      buildFormationMapPngIsolate,
      request.toIsolatePayload(),
    );
    if (!mounted) return;
    if (widget.formationMap?.sitesRevision != revision) return;
    if (!(widget.formationMap?.isActive ?? false)) {
      await _formationMapOverlay.clear();
      return;
    }
    final raster = formationMapResultFromIsolate(isolateResult);
    await _formationMapOverlay.sync(raster: raster);
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
    if (!widget.mapActive) return;
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
    if (!widget.rotateWithHeading || !widget.mapActive || !_ready) return;
    unawaited(MapboxViewportNative.disableIdleOnUserInteraction());
    _followPuckReassertTimer?.cancel();
    _followPuckReassertTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted ||
          !widget.rotateWithHeading ||
          !widget.mapActive ||
          !_ready) {
        return;
      }
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

  bool get _pinOverlayActive =>
      widget.rotateWithHeading || _detailPinsActive;

  Future<void> _setDetailPinsActive(bool active) async {
    if (_detailPinsActive == active) return;
    _detailPinsActive = active;
    // Rotate mode owns circle opacity while active.
    if (widget.rotateWithHeading) return;
    await _annotations?.setRotateModePaused(active);
    if (!mounted) return;
    if (active && widget.mapActive) {
      _syncRotateOverlayFrame();
      setState(() {});
    } else {
      setState(() => _visibleRotateSites = const []);
      widget.rotateCardCount?.value = 0;
      _scheduleAnnotationSync();
    }
  }

  Future<void> _applyRotateMarkerMode(bool rotate) async {
    if (rotate) {
      await _annotations?.setRotateModePaused(true);
      if (!mounted) return;
      if (widget.mapActive) {
        _setRotateOverlayTickerActive(true);
        // Keep circle annotations warm under opacity 0 while rotate is on.
        _scheduleAnnotationSync();
      }
      return;
    }

    _setRotateOverlayTickerActive(false);
    final wantPins = _lastKnownZoom >= MapConfig.sitePinDetailZoom;
    _detailPinsActive = wantPins;
    await _annotations?.setRotateModePaused(wantPins);
    if (!mounted) return;
    if (wantPins && widget.mapActive) {
      _syncRotateOverlayFrame();
      setState(() {});
    } else {
      setState(() => _visibleRotateSites = const []);
      widget.rotateCardCount?.value = 0;
    }
    _scheduleAnnotationSync();
  }

  /// Freeze Mapbox rendering work while shell screens are open (scrim backdrop
  /// keeps the last frame), then restore when the map is active again.
  ///
  /// Hides site / aerial / formation / rotate overlays, cancels FollowPuck
  /// tracking, and disables the location puck — the main GPU drains when the
  /// map is only a dimmed backdrop.
  Future<void> _setMapOverlaysVisible(bool visible) async {
    if (!visible) {
      _followPuckReassertTimer?.cancel();
      _setRotateOverlayTickerActive(false);
      widget.camera.clearPendingFollow();
      if (mounted) {
        setState(() {
          _visibleRotateSites = const [];
          _detailPinsActive = false;
          // Idle cancels FollowPuck / camera animations without flying away.
          _viewport = const IdleViewportState();
        });
      }
      widget.rotateCardCount?.value = 0;
      final map = _map;
      await Future.wait([
        _annotations?.setRotateModePaused(true) ?? Future<void>.value(),
        _aerialReconAnnotations?.clear() ?? Future<void>.value(),
        _orbitSurveyOverlay.clear(),
        _formationMapOverlay.clear(),
        if (map != null)
          map.location.updateSettings(
            LocationComponentSettings(enabled: false),
          ),
        if (map != null) map.reduceMemoryUse(),
      ]);
      return;
    }
    if (!_ready) return;
    await _enableLocationPuck();
    if (!mounted || !widget.mapActive) return;
    if (widget.rotateWithHeading) {
      _enterFollowPuck(animated: false);
    }
    await _applyRotateMarkerMode(widget.rotateWithHeading);
    if (!mounted || !widget.mapActive) return;
    _lastOrbitSurveySitesRevision = -1;
    _lastFormationMapSitesRevision = -1;
    await Future.wait([
      _syncToolSession(),
      _syncOrbitSurvey(),
      _syncFormationMap(),
    ]);
  }

  void _syncRotateOverlayFrame() {
    if (!_pinOverlayActive || !widget.mapActive || !_ready) return;
    final size = _viewportSize;
    final map = _map;
    if (size == null || map == null) return;
    _overlayController.syncFrame(
      map: map,
      sites: widget.sites,
      viewportSize: size,
      cullCenter: _effectiveLocation,
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
    final location = _effectiveLocation;
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
      unawaited(_syncToolSession());
    }

    // North-fixed GPS follow only — rotate mode is owned by FollowPuck.
    // Skip when *exiting* rotate: [applyOrientationMode] already flyTos flat
    // north-up; an instant followLocation setCamera would snap over that.
    final shouldFollow = widget.followUser && !widget.rotateWithHeading;
    final exitingRotate =
        oldWidget.rotateWithHeading && !widget.rotateWithHeading;
    if (shouldFollow &&
        !exitingRotate &&
        _effectiveLocation != null &&
        (oldWidget.followUser != widget.followUser ||
            (widget.locationListenable == null &&
                oldWidget.currentLocation != widget.currentLocation))) {
      unawaited(
        widget.camera.followLocation(
          _effectiveLocation!,
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
      } else if (_detailPinsActive) {
        _syncRotateOverlayFrame();
      }
      _annotationDebounce?.cancel();
      unawaited(_switchDatasetAndSync());
    } else if (oldWidget.sites != widget.sites) {
      // Same dataset: debounce circle sync; pin overlay updates immediately.
      if (widget.rotateWithHeading || _detailPinsActive) {
        _syncRotateOverlayFrame();
      }
      _scheduleAnnotationSync();
    }
    // Location cull-center updates; heading is owned by FollowPuck / ticker —
    // do not rebuild-sync on headingDeg (would fight compass decoupling).
    if ((widget.rotateWithHeading || _detailPinsActive) &&
        widget.locationListenable == null &&
        oldWidget.currentLocation != widget.currentLocation) {
      _liveLocation = widget.currentLocation;
      _syncRotateOverlayFrame();
    }
    if (oldWidget.locationListenable != widget.locationListenable) {
      oldWidget.locationListenable?.removeListener(_onLocationListenable);
      widget.locationListenable?.addListener(_onLocationListenable);
      _liveLocation =
          widget.locationListenable?.value ?? widget.currentLocation;
    } else if (widget.locationListenable == null &&
        oldWidget.currentLocation != widget.currentLocation) {
      _liveLocation = widget.currentLocation;
    }
    if (oldWidget.mapActive != widget.mapActive ||
        oldWidget.rotateWithHeading != widget.rotateWithHeading) {
      if (oldWidget.mapActive != widget.mapActive) {
        unawaited(_setMapOverlaysVisible(widget.mapActive));
      } else if (widget.rotateWithHeading && widget.mapActive && _ready) {
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
      unawaited(_enableLocationPuck());
    }
    if (oldWidget.aerialRecon != widget.aerialRecon) {
      oldWidget.aerialRecon?.removeListener(_onAerialReconChanged);
      oldWidget.aerialRecon?.progressTickListenable
          .removeListener(_onAerialProgressTick);
      widget.aerialRecon?.addListener(_onAerialReconChanged);
      widget.aerialRecon?.progressTickListenable
          .addListener(_onAerialProgressTick);
      unawaited(_syncToolSession());
    }
    if (oldWidget.orbitSurvey != widget.orbitSurvey) {
      oldWidget.orbitSurvey?.removeListener(_onOrbitSurveyChanged);
      widget.orbitSurvey?.addListener(_onOrbitSurveyChanged);
      _lastOrbitSurveySitesRevision = -1;
      unawaited(_syncOrbitSurvey());
    }
    if (oldWidget.formationMap != widget.formationMap) {
      oldWidget.formationMap?.removeListener(_onFormationMapChanged);
      widget.formationMap?.addListener(_onFormationMapChanged);
      _lastFormationMapSitesRevision = -1;
      unawaited(_syncFormationMap());
    }
    if (oldWidget.showPastAerialRoutes != widget.showPastAerialRoutes ||
        oldWidget.showAerialReconOverlays != widget.showAerialReconOverlays) {
      unawaited(_syncToolSession());
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    widget.camera.attach(map);
    widget.camera.rotateWithHeading = widget.rotateWithHeading;
    unawaited(_applyBasemapLook(force: true));
    unawaited(_seedAfterLayout());

    try {
      // Paint order = creation order: shadow → rim → fill → highlight → selection.
      final shadowManager =
          await map.annotations.createCircleAnnotationManager();
      final rimManager =
          await map.annotations.createCircleAnnotationManager();
      final manager = await map.annotations.createCircleAnnotationManager();
      final highlightManager =
          await map.annotations.createCircleAnnotationManager();
      final selectionDotManager =
          await map.annotations.createCircleAnnotationManager();
      final annotations = MapboxSiteAnnotations(onSiteTap: _onSiteTap);
      await annotations.attach(
        shadowManager: shadowManager,
        rimManager: rimManager,
        manager: manager,
        highlightManager: highlightManager,
        selectionDotManager: selectionDotManager,
      );
      _annotations?.dispose();
      _annotations = annotations;

      final lineManager =
          await map.annotations.createPolylineAnnotationManager();
      final scoutManager =
          await map.annotations.createPointAnnotationManager();
      final aerial = MapboxAerialAnnotations();
      await aerial.attach(
        lineManager: lineManager,
        scoutManager: scoutManager,
        onScoutTap: (sessionId) {
          final recon = widget.aerialRecon;
          if (recon == null) return;
          for (final session in recon.sessions) {
            if (session.sessionId == sessionId) {
              recon.focusSession(session);
              return;
            }
          }
        },
      );
      _aerialReconAnnotations?.dispose();
      _aerialReconAnnotations = aerial;

      _orbitSurveyOverlay.attach(map);
      _formationMapOverlay.attach(map);
      unawaited(_syncOrbitSurvey());
      unawaited(_syncFormationMap());

      await _applyGestureMode();
      _scheduleAnnotationSync();
      unawaited(_syncToolSession());
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
    _lastOrbitSurveySitesRevision = -1;
    _lastFormationMapSitesRevision = -1;
    unawaited(_syncOrbitSurvey());
    unawaited(_syncFormationMap());
  }

  void _onMapLoaded(MapLoadedEventData data) {
    _styleLoaded = true;
    unawaited(_applyBasemapLook());
    unawaited(_seedAfterLayout());
    _lastOrbitSurveySitesRevision = -1;
    _lastFormationMapSitesRevision = -1;
    unawaited(_syncOrbitSurvey());
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
        await _enableLocationPuck();
      } catch (_) {}

      if (widget.rotateWithHeading) {
        _enterFollowPuck();
      } else {
        await widget.camera.seedCamera(
          center: _effectiveLocation ?? _seedCenter,
          zoom: _seedZoom,
          headingDeg: _liveHeadingDeg,
        );
      }

      _cameraSeeded = true;
      if (!mounted) return;
      _markInternallyReady();
      _lastKnownZoom = _seedZoom;
      unawaited(_applyRotateMarkerMode(widget.rotateWithHeading));
      if (widget.rotateWithHeading) {
        _setRotateOverlayTickerActive(true);
      } else {
        if (_seedZoom >= MapConfig.sitePinDetailZoom) {
          unawaited(_setDetailPinsActive(true));
        }
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

  Future<void> _syncToolSession() async {
    final aerial = _aerialReconAnnotations;
    final controller = widget.aerialRecon;
    if (aerial == null || !_ready) return;
    try {
      // Keep rotate mode uncluttered — no scout loops/pucks over FollowPuck.
      // Archive mode never shows recon overlays.
      // Shell overlays (catalog/tools) keep the map as a clean backdrop.
      if (!widget.mapActive ||
          widget.rotateWithHeading ||
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
    final zoom = data.cameraState.zoom;
    final zoomChanged = (zoom - _lastKnownZoom).abs() > 0.01;
    _lastKnownZoom = zoom;
    if (zoomChanged) {
      _syncDiscoveryPulse();
    }
    if (widget.rotateWithHeading) {
      // Rotate mini-cards are driven by the vsync ticker only. Syncing here
      // too queued stale projections and made cards jitter behind FollowPuck.
      return;
    }
    widget.onZoomChanged(zoom);
    // Update marker size immediately while zooming (no debounce / bucket wait).
    final annotations = _annotations;
    if (annotations != null && !_detailPinsActive) {
      unawaited(annotations.applyZoomRadius(zoom));
    }
    final wantPins = zoom >= MapConfig.sitePinDetailZoom;
    if (wantPins != _detailPinsActive) {
      unawaited(_setDetailPinsActive(wantPins));
    } else if (_detailPinsActive) {
      _syncRotateOverlayFrame();
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
          if (sizeChanged &&
              (widget.rotateWithHeading || _detailPinsActive) &&
              _ready) {
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
            // Soft sandstone grade — ColorFilter doesn't compose with Mapbox.
            const IgnorePointer(
              child: ColoredBox(color: MapChromeTheme.mapSandstoneWash),
            ),
            // Below site cards / chrome; tool HUDs live in MapScreen under FABs.
            if (widget.mapActive && _ready)
              Consumer<TerrainEchoController>(
                builder: (context, echo, _) {
                  if (!echo.isActive) return const SizedBox.shrink();
                  return TerrainEchoOverlay(
                    camera: widget.camera,
                    rotateWithHeading: widget.rotateWithHeading,
                    zoom: _lastKnownZoom,
                  );
                },
              ),
            if (widget.mapActive && _ready && _ridgeGlassPulseActive)
              RidgeGlassPulseOverlay(
                camera: widget.camera,
                baseVisibilityM:
                    _resolveVisibilityDistanceM(ignoreActiveTool: true),
                fullVisibilityM: _resolveVisibilityDistanceM(),
                rotateWithHeading: widget.rotateWithHeading,
                zoom: _lastKnownZoom,
              ),
            // Mode 1 only (north-fixed, not following). Hidden while centered.
            if (widget.mapActive &&
                !widget.rotateWithHeading &&
                !widget.followUser &&
                _ready)
              const MapCenterCrosshair(),
            if (widget.mapActive &&
                (widget.rotateWithHeading || _detailPinsActive) &&
                _ready)
              Positioned.fill(
                child: MapRotateSiteCardOverlay(
                  visibleSites: _visibleRotateSites,
                  selectedSiteId: widget.selectedSite?.siteId,
                  onSiteTap: _onRotateMiniCardTap,
                ),
              ),
            // Translucent so mini-card taps still work; detects pinch-out to
            // leave rotate mode (FollowPuck locks Mapbox pinch gestures).
            if (widget.mapActive && widget.rotateWithHeading && _ready)
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
