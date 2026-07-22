import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/field_session_coordinator.dart';
import '../../controllers/map_controller.dart' as map_data;
import '../../controllers/splash_hold_provider.dart';
import '../../controllers/theme_controller.dart';
import '../../models/site.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/site_service.dart';
import '../../shell/map_chrome_insets.dart';
import '../../widgets/common/chrome_fab.dart';
import '../../widgets/dino/dinosaur_filter_fab.dart';
import '../../widgets/map/map_control_buttons.dart';
import '../../widgets/map/mapbox_camera_coordinator.dart';
import '../../widgets/map/mapbox_field_map.dart';
import '../../widgets/map/mapbox_site_annotations.dart';
import '../../widgets/map/site_filter_sheet.dart';
import '../../widgets/map/site_map_card_dialog.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.isActive = false,
  });

  final bool isActive;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapboxCameraCoordinator _mapboxCamera = MapboxCameraCoordinator();

  bool _mapboxReady = false;
  bool _splashDismissed = false;
  double _zoomLevel = MapConfig.mapboxRotateZoom;
  bool _didInitialCenter = false;
  bool _followUser = true;
  /// false = north-fixed Mapbox; true = map bearing follows phone.
  bool _rotateMap = true;
  int? _hiddenRotateSiteId;
  LatLng? _lastFollowedLocation;
  String? _scanBannerMessage;
  String? _mapboxBannerMessage;
  Timer? _scanBannerTimer;
  Timer? _splashSafetyTimer;

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
    _scanBannerTimer?.cancel();
    _splashSafetyTimer?.cancel();
    super.dispose();
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

  void _showScanBanner(String message, {bool autoDismiss = true}) {
    _scanBannerTimer?.cancel();
    setState(() => _scanBannerMessage = message);
    if (!autoDismiss) return;
    _scanBannerTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _scanBannerMessage = null);
    });
  }

  Future<void> _onScanFieldArea() async {
    if (!_mapboxReady) return;
    final center = await _mapboxCamera.currentCenter();
    if (center == null) {
      _showScanBanner('Could not read map center');
      return;
    }
    _showScanBanner('Field site scan queued…', autoDismiss: false);
    unawaited(_runAdminFieldScan(center));
  }

  Future<void> _runAdminFieldScan(LatLng center) async {
    final siteService = SiteService();
    try {
      final response = await context
          .read<FieldSessionCoordinator>()
          .scanAt(center);
      if (!mounted) return;
      if (response == null) {
        _showScanBanner('Could not queue field site scan');
        return;
      }

      final jobId = response.jobId;
      if (jobId == null) {
        _showScanBanner(
          response.accepted
              ? 'Field site scan queued'
              : 'Scan already running for this area',
        );
        return;
      }

      if (!response.accepted) {
        _showScanBanner(
          'Scan already running — waiting for result…',
          autoDismiss: false,
        );
      }

      final status = await siteService.waitForFieldEnsureJob(jobId);
      if (!mounted) return;

      if (status.isFailed) {
        _showScanBanner(
          status.errorMessage?.trim().isNotEmpty == true
              ? 'Scan failed: ${status.errorMessage}'
              : 'Field site scan failed',
        );
        return;
      }

      final written = status.generated ?? 0;
      final after = status.totalInRadius ?? 0;
      final found = (after - written).clamp(0, after);
      final radiusKm = status.radiusKm;
      final radiusLabel = radiusKm == radiusKm.roundToDouble()
          ? '${radiusKm.toInt()} km'
          : '${radiusKm.toStringAsFixed(1)} km';
      _showScanBanner('Found $found in $radiusLabel · wrote $written');
      context.read<map_data.MapController>().scheduleFieldPollAfterEnsure();
    } catch (_) {
      if (!mounted) return;
      _showScanBanner('Could not complete field site scan');
    } finally {
      siteService.dispose();
    }
  }

  void _openFilterSheet(map_data.MapController mapData, bool isFieldMode) {
    SiteFilterSheet.show(
      context,
      initialFilters: mapData.filters.copyWith(filterByStatus: isFieldMode),
      showStatusSection: isFieldMode,
      onApply: mapData.applyFilters,
    );
  }

  Future<void> _onSiteTap(SiteSummary site) async {
    final mapData = context.read<map_data.MapController>();
    // Keep selection after the card closes; only another tap replaces it.
    mapData.selectSite(site);
    if (_rotateMap) {
      setState(() => _hiddenRotateSiteId = site.siteId);
    }
    final displayFuture = mapData.siteForDisplay(site);
    if (!_rotateMap) {
      unawaited(_panToSite(site));
    }
    final displaySite = await displayFuture;
    if (!mounted) return;
    await showSiteMapCardDialog(context, displaySite);
    if (mounted) {
      setState(() => _hiddenRotateSiteId = null);
    }
  }

  void _onMapboxError(Object error) {
    if (!mounted) return;
    setState(() {
      _mapboxBannerMessage = 'Mapbox failed: $error';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFieldMode = context.watch<CatalogModeController>().isField;
    final auth = context.watch<AuthController>();
    final isAdmin = auth.currentUser?.isAdmin ?? false;
    final basemapTheme = context.watch<ThemeController>().mapBasemapTheme;
    final avatarUrl = AuthService.imageUrl(auth.currentUser?.profileImage);

    return Consumer2<map_data.MapController, LocationService>(
      builder: (context, mapData, locationService, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!isAdmin && mapData.showAllFieldSites) {
            mapData.setShowAllFieldSites(false);
          }
          _setInitialCamera(locationService: locationService);
          _maybeFollowUser(locationService);
          _consumePendingFocus();
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
                child: MapboxFieldMap(
                  camera: _mapboxCamera,
                  rotateWithHeading: _rotateMap,
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
                  followUser: _followUser || _rotateMap,
                  initialCenter: startCenter,
                  initialZoom: _zoomLevel,
                  basemapTheme: basemapTheme,
                  avatarImageUrl: avatarUrl.isEmpty ? null : avatarUrl,
                  onSiteTap: _onSiteTap,
                  onFollowCancelled: () {
                    // Rotate mode is always locked to the user.
                    if (_rotateMap) return;
                    if (_followUser) setState(() => _followUser = false);
                  },
                  onZoomChanged: _onMapboxZoomChanged,
                  onReadyChanged: (ready) {
                    if (!mounted) return;
                    setState(() => _mapboxReady = ready);
                    if (ready) {
                      _consumePendingFocus();
                      _setInitialCamera(locationService: locationService);
                      _dismissSplash();
                    }
                  },
                  onError: _onMapboxError,
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
            if (_scanBannerMessage != null)
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
            if (mapData.loading)
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
            if (mapData.error != null)
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
            MapControlButtons(
              currentZoom: _zoomLevel,
              onZoomChanged: _onZoomChanged,
              onCenterLocation: () => _centerOnLocation(locationService),
              rotateMap: _rotateMap,
              onToggleRotation: _toggleRotationMode,
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
            if (locationService.error != null)
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
