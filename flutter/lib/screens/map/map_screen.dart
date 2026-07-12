import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/map_controller.dart' as map_data;
import '../../models/fossil.dart';
import '../../services/location_service.dart';
import '../../widgets/fossil/fossil_filter_fab.dart';
import '../../widgets/fossil/fossil_filter_sheet.dart';
import '../../widgets/map/fossil_map_card_dialog.dart';
import '../../widgets/map/fossil_markers_layer.dart';
import '../../widgets/map/location_marker_layer.dart';
import '../../widgets/map/map_control_buttons.dart';
import '../../widgets/map/map_tile_layer.dart';

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
  final fm.MapController _mapController = fm.MapController();

  StreamSubscription<fm.MapEvent>? _mapSub;
  bool _mapReady = false;
  double _zoomLevel = MapConfig.initialZoom;
  bool _centeredOnUser = false;
  bool _rotateMap = false;

  @override
  void initState() {
    super.initState();
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
    _mapSub?.cancel();
    super.dispose();
  }

  void _activateIfNeeded() {
    if (!widget.isActive) {
      context.read<LocationService>().stop();
      context.read<map_data.MapController>().pause();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) return;
      context.read<LocationService>().start();
      context.read<map_data.MapController>().load();
    });
  }

  void _onMapEvent(fm.MapEvent event) {
    if (!mounted) return;
    try {
      final zoom = _mapController.camera.zoom;
      if (zoom != _zoomLevel) {
        setState(() => _zoomLevel = zoom);
      } else if (event is fm.MapEventMove) {
        setState(() {});
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
    _mapController.move(location, _mapController.camera.zoom);
  }

  void _onZoomChanged(double zoom) {
    _mapController.move(_mapController.camera.center, zoom);
  }

  bool _isCenteredOnCurrent(LocationService locationService) {
    final current = locationService.currentLocation;
    if (current == null || !_mapReady) return true;

    final center = _mapController.camera.center;
    const distance = Distance();
    final meters = distance(center, current);
    return meters < 50;
  }

  LatLng? _safeCameraCenter() {
    if (!_mapReady) return null;
    try {
      return _mapController.camera.center;
    } catch (_) {
      return null;
    }
  }

  fm.LatLngBounds? _safeVisibleBounds() {
    if (!_mapReady) return null;
    try {
      return _mapController.camera.visibleBounds;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onFossilTap(FossilSummary fossil) async {
    final mapData = context.read<map_data.MapController>();
    mapData.selectFossil(fossil);
    await showFossilMapCardDialog(context, fossil);
    if (!mounted) return;
    mapData.clearSelection();
  }

  void _openFilterSheet(map_data.MapController mapData) {
    FossilFilterSheet.show(
      context,
      initialFilters: mapData.filters,
      catalogTotal: mapData.totalCatalog > 0 ? mapData.totalCatalog : null,
      onApply: mapData.applyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      fm.InteractiveFlag.drag,
                ),
              ),
              children: [
                const MapTileLayer(),
                FossilMarkersLayer(
                  fossils: mapData.geoFossils,
                  zoomLevel: _zoomLevel,
                  mapReady: _mapReady,
                  visibleBounds: _safeVisibleBounds(),
                  selectedFossil: mapData.selectedFossil,
                  onFossilTap: _onFossilTap,
                ),
                LocationMarkerLayer(
                  currentLocation: locationService.currentLocation,
                  cameraCenter: _safeCameraCenter(),
                  headingDeg: locationService.headingDeg,
                  rotateMap: _rotateMap,
                  mapReady: _mapReady,
                  isCenteredOnCurrent:
                      _isCenteredOnCurrent(locationService),
                  onTapCenter: () => _centerOnLocation(locationService),
                ),
              ],
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
                          Text(_fossilLoadingLabel(mapData)),
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
              onRefresh: mapData.refresh,
              isRefreshing: mapData.loading,
              filterFab: FossilFilterFab(
                heroTag: 'map_filter_fab',
                hasActiveFilters: mapData.hasActiveFilters,
                onPressed: () => _openFilterSheet(mapData),
              ),
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

  String _fossilLoadingLabel(map_data.MapController mapData) {
    if (mapData.totalCatalog > 0) {
      return 'Loading fossils… ${mapData.geoFossilCount} found '
          '(${mapData.loadedCatalog}/${mapData.totalCatalog})';
    }
    if (mapData.geoFossilCount > 0) {
      return 'Loading fossils… ${mapData.geoFossilCount} found';
    }
    return 'Loading fossils…';
  }
}
