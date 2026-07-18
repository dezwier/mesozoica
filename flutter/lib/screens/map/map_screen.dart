import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/catalog_mode_controller.dart';
import '../../controllers/field_session_coordinator.dart';
import '../../controllers/map_controller.dart' as map_data;
import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../widgets/map/location_marker_layer.dart';
import '../../widgets/map/map_control_buttons.dart';
import '../../widgets/map/map_tile_layer.dart';
import '../../widgets/map/site_map_card_dialog.dart';
import '../../widgets/map/site_markers_layer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.isActive = false,
  });

  final bool isActive;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final fm.MapController _mapController = fm.MapController();
  late final AnimatedMapController _animatedMapController;

  StreamSubscription<fm.MapEvent>? _mapSub;
  bool _mapReady = false;
  double _zoomLevel = MapConfig.initialZoom;
  bool _centeredOnUser = false;
  bool _rotateMap = false;
  bool _scanning = false;
  String? _scanBannerMessage;
  Timer? _scanBannerTimer;

  @override
  void initState() {
    super.initState();
    _animatedMapController = AnimatedMapController(
      vsync: this,
      mapController: _mapController,
      duration: const Duration(milliseconds: 500),
    );
    _mapSub = _mapController.mapEventStream.listen(_onMapEvent);
    _activateIfNeeded();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activateIfNeeded();
  }

  @override
  void dispose() {
    _scanBannerTimer?.cancel();
    _mapSub?.cancel();
    _animatedMapController.dispose();
    super.dispose();
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
    });
  }

  void _onMapEvent(fm.MapEvent event) {
    if (!mounted) return;
    try {
      final zoom = event.camera.zoom;
      if (zoom != _zoomLevel) {
        setState(() => _zoomLevel = zoom);
      }
    } catch (_) {
      // Map controller not ready yet.
    }
  }

  void _updateMapRotation(double headingDeg) {
    if (!_rotateMap || !_mapReady) return;
    try {
      _mapController.rotate(-headingDeg);
    } catch (_) {
      // Map controller not ready yet.
    }
  }

  void _toggleRotationMode(double headingDeg) {
    setState(() {
      _rotateMap = !_rotateMap;
      if (_mapReady) {
        _mapController.rotate(_rotateMap ? -headingDeg : 0);
      }
    });
  }

  void _setInitialCamera({
    required LocationService locationService,
  }) {
    if (!_mapReady || _centeredOnUser) return;

    if (locationService.hasLocation) {
      _mapController.move(
        locationService.currentLocation!,
        MapConfig.initialZoom,
      );
      _centeredOnUser = true;
    }
  }

  void _centerOnLocation(LocationService locationService) {
    final location = locationService.currentLocation;
    if (location == null || !_mapReady) return;
    _animatedMapController.centerOnPoint(
      location,
      zoom: _mapController.camera.zoom,
    );
  }

  void _onZoomChanged(double zoom) {
    _mapController.move(_mapController.camera.center, zoom);
  }

  void _showScanBanner(String message) {
    _scanBannerTimer?.cancel();
    setState(() => _scanBannerMessage = message);
    _scanBannerTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _scanBannerMessage = null);
    });
  }

  String _scanRequestBannerMessage(FieldEnsureResponse response) {
    if (!response.accepted) {
      return 'Scan already queued for this map area';
    }
    if (response.missing <= 0) {
      return 'This map area already has enough field sites';
    }
    return 'Field site scan requested — new sites will appear when ready';
  }

  Future<void> _onScanFieldArea() async {
    if (!_mapReady || _scanning) return;

    final center = _mapController.camera.center;
    setState(() => _scanning = true);
    try {
      final response =
          await context.read<FieldSessionCoordinator>().scanAt(center);
      if (!mounted) return;
      if (response != null) {
        _showScanBanner(_scanRequestBannerMessage(response));
      }
    } catch (error) {
      if (mounted) {
        _showScanBanner('Could not request field site scan');
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _onSiteTap(SiteSummary site) async {
    final mapData = context.read<map_data.MapController>();
    mapData.selectSite(site);
    final displaySite = await mapData.siteForDisplay(site);
    if (!mounted) return;
    await showSiteMapCardDialog(context, displaySite);
    if (!mounted) return;
    mapData.clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final isFieldMode = context.watch<CatalogModeController>().isField;

    return Consumer2<map_data.MapController, LocationService>(
      builder: (context, mapData, locationService, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _setInitialCamera(locationService: locationService);
          _updateMapRotation(locationService.headingDeg);
        });

        final startCenter =
            locationService.currentLocation ?? MapConfig.defaultCenter;

        return Stack(
          children: [
            fm.FlutterMap(
              mapController: _mapController,
              options: fm.MapOptions(
                initialCenter: startCenter,
                initialZoom: _zoomLevel,
                minZoom: MapConfig.minZoom,
                maxZoom: MapConfig.maxZoom,
                backgroundColor: Theme.of(context).colorScheme.surface,
                cameraConstraint: fm.CameraConstraint.contain(
                  bounds: fm.LatLngBounds(
                    const LatLng(-85, -180),
                    const LatLng(85, 180),
                  ),
                ),
                onMapReady: () {
                  if (!mounted) return;
                  setState(() => _mapReady = true);
                  if (_rotateMap) {
                    _mapController.rotate(-locationService.headingDeg);
                  }
                },
                interactionOptions: const fm.InteractionOptions(
                  flags: fm.InteractiveFlag.pinchZoom |
                      fm.InteractiveFlag.doubleTapZoom |
                      fm.InteractiveFlag.scrollWheelZoom |
                      fm.InteractiveFlag.drag |
                      fm.InteractiveFlag.flingAnimation,
                ),
              ),
              children: [
                const MapTileLayer(),
                SiteMarkersLayer(
                  sites: mapData.geoSites,
                  mapReady: _mapReady,
                  selectedSite: mapData.selectedSite,
                  onSiteTap: _onSiteTap,
                ),
                LocationMarkerLayer(
                  currentLocation: locationService.currentLocation,
                  headingDeg: locationService.headingDeg,
                  rotateMap: _rotateMap,
                  mapReady: _mapReady,
                  onTapCenter: () => _centerOnLocation(locationService),
                ),
              ],
            ),
            if (_scanBannerMessage != null)
              Positioned(
                top: 12,
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
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scanBannerMessage!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                top: locationService.error != null ? 56 : 12,
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
                top: 12,
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
              onToggleRotation: () =>
                  _toggleRotationMode(locationService.headingDeg),
              filterFab: isFieldMode
                  ? FloatingActionButton.small(
                      heroTag: 'scan_field_area',
                      onPressed: _scanning ? null : _onScanFieldArea,
                      tooltip: 'Scan map center for field sites',
                      child: _scanning
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                            )
                          : const Icon(Icons.radar_outlined),
                    )
                  : null,
            ),
            if (locationService.error != null)
              Positioned(
                top: mapData.loading ? 56 : 12,
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
