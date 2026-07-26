import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/aerial_mission_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/field_discovery_coordinator.dart';
import '../../controllers/field_session_coordinator.dart';
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
import '../../widgets/map/guidance_overlay.dart';
import '../../widgets/map/map_control_buttons.dart';
import '../../widgets/map/map_perf_hud.dart';
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
  });

  final bool isActive;

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
    _activateIfNeeded();
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
    final isAdmin = auth.currentUser?.isAdmin ?? false;
    final basemapTheme = context.watch<ThemeController>().mapBasemapTheme;
    final mapBrightness = Theme.of(context).brightness;
    final avatarUrl = AuthService.imageUrl(auth.currentUser?.profileImage);
    final aerialRecon = context.watch<AerialMissionController>();
    final aerialDrawMode = aerialRecon.isDrawMode;
    final guidance = context.watch<GuidanceSessionController>();

    // Force north-fixed while drawing a scout loop.
    if (aerialDrawMode && _rotateMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.read<AerialMissionController>().isDrawMode && _rotateMap) {
          setState(() {
            _rotateMap = false;
            _followUser = true;
          });
          context.read<GuidanceSessionController>().onRotateModeExited();
        }
      });
    }

    if (guidance.requestEnterRotate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final g = context.read<GuidanceSessionController>();
        if (!g.requestEnterRotate) return;
        g.consumeEnterRotateRequest();
        _ensureRotationMode();
      });
    }

    return Consumer2<map_data.MapController, LocationService>(
      builder: (context, mapData, locationService, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!isAdmin && mapData.showAllFieldSites) {
            mapData.setShowAllFieldSites(false);
          }
          _setInitialCamera(locationService: locationService);
          _maybeFollowUser(locationService);
          _maybeFollowAerialScout();
          _consumePendingFocus();
          _consumePendingAerialFocus();
        });

        final startCenter =
            locationService.currentLocation ?? MapConfig.defaultCenter;
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
                    hiddenRotateSiteId: _hiddenRotateSiteId,
                    markerDatasetKey: [
                      isFieldMode
                          ? (mapData.showAllFieldSites
                              ? 'field:all'
                              : 'field:linked')
                          : 'archive',
                      mapData.filters.markerFilterKey,
                    ].join('|'),
                    currentLocation: locationService.currentLocation,
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
                      }
                    },
                    onRotatePinchZoomOut: _exitToNorthFixedCentered,
                    onZoomChanged: _onMapboxZoomChanged,
                    onReadyChanged: (ready) {
                      if (!mounted) return;
                      setState(() => _mapboxReady = ready);
                      if (ready) {
                        _consumePendingFocus();
                        _consumePendingAerialFocus();
                        _setInitialCamera(locationService: locationService);
                        _dismissSplash();
                      }
                    },
                    onError: _onMapboxError,
                  ),
                ),
              ),
            if (isAdmin && widget.isActive && !aerialDrawMode)
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
            if (mapData.loading && !aerialDrawMode)
              Positioned(
                top: topInset + (locationService.error != null ? 44 : 0),
                left: 0,
                right: 0,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(_siteLoadingLabel(mapData)),
                        ],
                      ),
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
            if (!aerialDrawMode)
              MapControlButtons(
                currentZoom: _zoomLevel,
                onZoomChanged: _onZoomChanged,
                locationFabMode: _locationFabMode,
                onLocationFabPressed: () =>
                    _onLocationFabPressed(locationService),
                bottom: fabBottom,
                leadingActions: [
                  if (isFieldMode && isAdmin) ...[
                    ChromeFab(
                      heroTag: 'show_all_field_sites',
                      tone: ChromeFabTone.grey,
                      active: mapData.showAllFieldSites,
                      onPressed: () {
                        mapData.setShowAllFieldSites(
                          !mapData.showAllFieldSites,
                        );
                      },
                      tooltip: mapData.showAllFieldSites
                          ? 'Showing all field sites'
                          : 'Show all field sites',
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
                    // Keep admin tools clearly above the regular map FABs.
                    const SizedBox(height: 28),
                  ],
                ],
                filterFab: DinosaurFilterFab(
                  heroTag: 'site_filter_fab',
                  hasActiveFilters: mapData.hasActiveFilters,
                  onPressed: () => _openFilterSheet(mapData, isFieldMode),
                ),
              ),
            if (locationService.error != null && !aerialDrawMode)
              Positioned(
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
                      locationService.error!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            if (aerialDrawMode)
              AerialMissionDrawOverlay(
                camera: _mapboxCamera,
                currentZoom: _zoomLevel,
                onZoomChanged: _onZoomChanged,
              )
            else if (aerialRecon.focusedMission != null)
              const AerialMissionFocusOverlay(),
            if (_rotateMap && !aerialDrawMode && guidance.isActive)
              const GuidanceOverlay(),
          ],
        );
      },
    );
  }

  String _siteLoadingLabel(map_data.MapController mapData) {
    if (context.read<CatalogModeController>().isField) {
      if (mapData.totalCatalog > 0) {
        return 'Loading field sites… ${mapData.geoSiteCount} found '
            '(${mapData.loadedCatalog}/${mapData.totalCatalog})';
      }
      if (mapData.geoSiteCount > 0) {
        return 'Loading field sites… ${mapData.geoSiteCount} found';
      }
      return 'Loading field sites…';
    }
    if (mapData.totalCatalog > 0) {
      return 'Loading sites… ${mapData.geoSiteCount} found '
          '(${mapData.loadedCatalog}/${mapData.totalCatalog})';
    }
    if (mapData.geoSiteCount > 0) {
      return 'Loading sites… ${mapData.geoSiteCount} found';
    }
    return 'Loading sites…';
  }
}
