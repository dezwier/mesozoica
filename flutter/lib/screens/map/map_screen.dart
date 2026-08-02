import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/aerial_mission_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/field_session_coordinator.dart';
import '../../controllers/formation_map_controller.dart';
import '../../controllers/orbit_survey_controller.dart';
import '../../controllers/terrain_echo_controller.dart';
import '../../controllers/fossil_catalog_controller.dart';
import '../../controllers/guidance_session_controller.dart';
import '../../controllers/map_controller.dart' as map_data;
import '../../controllers/site_catalog_controller.dart';
import '../../controllers/splash_hold_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/site.dart';
import '../../models/site_map_filters.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/site_service.dart';
import '../../services/tool_service.dart';
import '../../shell/map_chrome_insets.dart';
import '../../widgets/common/chrome_fab.dart';
import '../../widgets/dino/dinosaur_filter_fab.dart';
import '../../widgets/map/aerial_mission_draw_overlay.dart';
import '../../widgets/map/aerial_mission_focus_overlay.dart';
import '../../widgets/map/field_data_purge_dialog.dart';
import '../../widgets/map/formation_map_hud.dart';
import '../../widgets/map/orbit_survey_hud.dart';
import '../../widgets/map/terrain_echo_hud.dart';
import '../../widgets/map/terrain_echo_overlay.dart';
import '../../widgets/map/guidance_overlay.dart';
import '../../widgets/map/map_control_buttons.dart';
import '../../widgets/map/map_perf_hud.dart';
import '../../widgets/map/map_visible_bounds.dart';
import '../../widgets/map/mapbox_camera_coordinator.dart';
import '../../widgets/map/mapbox_field_map.dart';
import '../../widgets/map/mapbox_site_annotations.dart';
import '../../widgets/map/site_filter_sheet.dart';
import '../../widgets/map/site_map_card_dialog.dart';

part 'map_screen_camera.dart';
part 'map_screen_field_ops.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.isActive = false,
    this.showControls = true,
  });

  final bool isActive;

  /// When false, hides zoom / location / filter FABs (e.g. Catalog/Tools overlay).
  final bool showControls;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with _MapScreenCameraMixin, _MapScreenFieldOpsMixin {
  @override
  void initState() {
    super.initState();
    _activateIfNeeded();
    if (!MapConfig.hasMapboxAccessToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _dismissSplash();
      });
    }
    _splashSafetyTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || _splashDismissed) return;
      _dismissSplash();
    });
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent rebuilds (shell setState, auth, splash) recreate MapScreen; only
    // react when map foreground actually changes — otherwise startTracking
    // would refetch /api/.../missions/aerial on every notify.
    if (oldWidget.isActive != widget.isActive) {
      _activateIfNeeded();
    }
  }

  @override
  void dispose() {
    _disposeFieldOpsMixin();
    _disposeCameraMixin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFieldMode = context.watch<CatalogModeController>().isField;
    final auth = context.watch<AuthController>();
    final isAdmin = auth.isAdmin;
    final showAdminUi = auth.showAdminUi;
    final adminMode = auth.adminModeEnabled;
    final basemapTheme = context.watch<ThemeController>().mapBasemapTheme;
    final mapBrightness = Theme.of(context).brightness;
    final avatarUrl = AuthService.imageUrl(auth.currentUser?.profileImage);
    final aerialRecon = context.watch<AerialMissionController>();
    final aerialDrawMode = aerialRecon.isDrawMode;
    final guidance = context.watch<GuidanceSessionController>();
    final orbitSurvey = context.watch<OrbitSurveyController>();
    final formationMap = context.watch<FormationMapController>();
    final terrainEcho = context.watch<TerrainEchoController>();

    if (guidance.requestShowOnMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final g = context.read<GuidanceSessionController>();
        if (!g.requestShowOnMap) return;
        g.consumeShowOnMapRequest();
        _ensureGuidanceVisibleOnMap();
      });
    }

    if (orbitSurvey.requestShowOnMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final f = context.read<OrbitSurveyController>();
        if (!f.requestShowOnMap) return;
        f.consumeShowOnMapRequest();
        _ensureGuidanceVisibleOnMap();
      });
    }

    if (formationMap.requestShowOnMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final f = context.read<FormationMapController>();
        if (!f.requestShowOnMap) return;
        f.consumeShowOnMapRequest();
        _ensureGuidanceVisibleOnMap();
      });
    }

    if (terrainEcho.requestShowOnMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final e = context.read<TerrainEchoController>();
        if (!e.requestShowOnMap) return;
        e.consumeShowOnMapRequest();
        _ensureGuidanceVisibleOnMap();
      });
    }

    return Consumer<map_data.MapController>(
      builder: (context, mapData, _) {
        final locationService = context.read<LocationService>();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!showAdminUi && mapData.showAllFieldSites) {
            mapData.setShowAllFieldSites(false);
          }
          _setInitialCamera(locationService: locationService);
          _maybeFollowAerialScout();
          _consumePendingFocus();
          _consumePendingAerialFocus();
          _consumePendingDrawCamera();
        });

        final startCenter =
            locationService.locationListenable.value ??
                locationService.currentLocation ??
                MapConfig.defaultCenter;
        final topInset = MapChromeInsets.top(context);
        final fabBottom = MapChromeInsets.fabBottom(context);

        return Stack(
          children: [
            if (!MapConfig.hasMapboxAccessToken)
              const ColoredBox(
                color: Color(0xFFE8DFD4),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Mapbox token missing.\nRun with ./run.sh so '
                      '.dart_defines.json is applied.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: TickerMode(
                  enabled: widget.isActive,
                  child: MapboxFieldMap(
                    camera: _mapboxCamera,
                    rotateWithHeading: aerialDrawMode ? false : _rotateMap,
                    mapActive: widget.isActive,
                    sites: mapData.filteredGeoSites,
                    selectedSite: mapData.selectedSite,
                    markerDatasetKey: mapData.mapMarkerDatasetKey(
                      isFieldMode: isFieldMode,
                    ),
                    currentLocation: locationService.currentLocation,
                    locationListenable: locationService.locationListenable,
                    headingDeg: locationService.headingDeg,
                    headingListenable: locationService.headingListenable,
                    followUser: aerialDrawMode
                        ? false
                        : (_followUser || _rotateMap),
                    initialCenter: startCenter,
                    initialZoom: _zoomLevel,
                    basemapTheme: basemapTheme,
                    brightness: mapBrightness,
                    avatarImageUrl: avatarUrl.isEmpty ? null : avatarUrl,
                    rotateCardCount: _rotateCardCount,
                    aerialRecon: aerialRecon,
                    orbitSurvey: orbitSurvey,
                    formationMap: formationMap,
                    showAerialReconOverlays: isFieldMode,
                    showPastAerialRoutes: mapData.filters.showPastAerialRoutes,
                    onSiteTap: aerialDrawMode ? (_) {} : _onSiteTap,
                    onFollowCancelled: () {
                      // Rotate mode is always locked to the user.
                      if (_rotateMap) return;
                      if (_followUser || _followAerialScout) {
                        setState(() {
                          _followUser = false;
                          _followAerialScout = false;
                          _aerialFocusAnimating = false;
                        });
                        // Guidance sessions keep running until Stop / expiry.
                      }
                    },
                    onRotatePinchZoomOut: _exitToNorthFixedCentered,
                    onLocationPuckTap:
                        aerialDrawMode ? () {} : _enterRotationMode,
                    onZoomChanged: _onMapboxZoomChanged,
                    onReadyChanged: (ready) {
                      if (!mounted) return;
                      setState(() => _mapboxReady = ready);
                      if (ready) {
                        _consumePendingFocus();
                        _consumePendingAerialFocus();
                        _consumePendingDrawCamera();
                        _setInitialCamera(locationService: locationService);
                        _dismissSplash();
                      }
                    },
                    onError: _onMapboxError,
                  ),
                ),
              ),
            if (showAdminUi && widget.isActive && !aerialDrawMode)
              Positioned(
                top: topInset,
                left: 8,
                child: MapPerfHud(
                  rotateMap: _rotateMap,
                  followUser: _followUser || _rotateMap,
                  mapActive: widget.isActive,
                  mapboxReady: _mapboxReady,
                  rotateCardCount: _rotateCardCount,
                ),
              ),
            if (_mapboxBannerMessage != null)
              Positioned(
                top: topInset,
                left: 16,
                right: 16,
                child: Material(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _mapboxBannerMessage!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _mapboxBannerMessage = null),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_scanBannerMessage != null && !aerialDrawMode)
              Positioned(
                top: topInset,
                left: 16,
                right: 16,
                child: Material(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.radar_outlined,
                          size: 18,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scanBannerMessage!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (mapData.error != null && !aerialDrawMode)
              Positioned(
                top: topInset,
                left: 16,
                right: 16,
                child: Material(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            mapData.error!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: mapData.refresh,
                          icon: const Icon(Icons.refresh, size: 18),
                          tooltip: 'Retry',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!aerialDrawMode && widget.showControls)
              MapControlButtons(
                currentZoom: _zoomLevel,
                onZoomChanged: _onZoomChanged,
                locationFabMode: _locationFabMode,
                onLocationFabPressed: () =>
                    _onLocationFabPressed(locationService),
                bottom: fabBottom,
                leadingActions: [
                  if (isAdmin) ...[
                    if (isFieldMode && showAdminUi) ...[
                      ChromeFab(
                        heroTag: 'show_all_field_sites',
                        tone: mapData.showAllFieldSites
                            ? ChromeFabTone.warm
                            : ChromeFabTone.grey,
                        active: mapData.showAllFieldSites,
                        onPressed: () {
                          final enabling = !mapData.showAllFieldSites;
                          mapData.setShowAllFieldSites(enabling);
                          if (enabling) {
                            unawaited(_loadSitesInViewport());
                          }
                        },
                        tooltip: mapData.showAllFieldSites
                            ? 'Hide sites in view'
                            : 'Show all sites in view',
                        child: Icon(
                          mapData.showAllFieldSites
                              ? Icons.visibility
                              : Icons.visibility_outlined,
                        ),
                      ),
                      ChromeFab(
                        heroTag: 'scan_field_area',
                        tone: ChromeFabTone.grey,
                        onPressed: _onScanFieldArea,
                        tooltip: 'Scan map center for field sites',
                        child: const Icon(Icons.radar_outlined),
                      ),
                      ChromeFab(
                        heroTag: 'purge_field_data',
                        tone: ChromeFabTone.grey,
                        onPressed: _onPurgeFieldData,
                        tooltip: 'Delete field data',
                        child: const Icon(Icons.delete_forever_outlined),
                      ),
                    ],
                    ChromeFab(
                      heroTag: 'admin_mode_toggle',
                      tone: adminMode
                          ? ChromeFabTone.warm
                          : ChromeFabTone.grey,
                      active: adminMode,
                      onPressed: auth.toggleAdminMode,
                      tooltip: adminMode
                          ? 'Exit admin mode'
                          : 'Enter admin mode',
                      child: Icon(
                        adminMode
                            ? Icons.admin_panel_settings
                            : Icons.admin_panel_settings_outlined,
                      ),
                    ),
                  ],
                ],
                filterFab: DinosaurFilterFab(
                  heroTag: 'site_filter_fab',
                  hasActiveFilters: mapData.hasActiveFilters,
                  onPressed: () => _openFilterSheet(mapData, isFieldMode),
                ),
              ),
            Selector<LocationService, String?>(
              selector: (_, loc) => loc.error,
              builder: (context, locationError, _) {
                if (locationError == null || aerialDrawMode) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: topInset + (mapData.loading || isFieldMode ? 44 : 0),
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        locationError,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (aerialDrawMode && widget.isActive)
              AerialMissionDrawOverlay(
                camera: _mapboxCamera,
                currentZoom: _zoomLevel,
                onZoomChanged: _onZoomChanged,
              )
            else if (widget.isActive && aerialRecon.focusedMission != null)
              const AerialMissionFocusOverlay(),
            if (widget.isActive && !aerialDrawMode && guidance.isActive)
              GuidanceOverlay(
                rotateWithHeading: _rotateMap,
                followUser: _followUser || _rotateMap,
              ),
            if (widget.isActive && !aerialDrawMode && orbitSurvey.isActive)
              const OrbitSurveyHud(),
            if (widget.isActive && !aerialDrawMode && formationMap.isActive)
              const FormationMapHud(),
            if (widget.isActive && !aerialDrawMode && terrainEcho.isActive) ...[
              TerrainEchoOverlay(
                camera: _mapboxCamera,
                rotateWithHeading: _rotateMap,
              ),
              const TerrainEchoHud(),
            ],
          ],
        );
      },
    );
  }
}
