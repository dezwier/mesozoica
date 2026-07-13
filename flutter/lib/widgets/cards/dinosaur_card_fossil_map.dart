import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/map_config.dart';
import '../../models/fossil.dart';
import '../../services/fossil_service.dart';
import '../../theme/dino_card_theme.dart';
import '../map/fossil_map_card_dialog.dart';
import '../map/fossil_marker.dart';
import '../map/map_tile_layer.dart';

/// World map showing geolocated fossil occurrences on the dinosaur card back.
class DinosaurCardFossilMap extends StatefulWidget {
  const DinosaurCardFossilMap({
    super.key,
    required this.dinosaurId,
    this.fossilService,
    this.tileLayerBuilder = _defaultTileLayerBuilder,
  });

  final int dinosaurId;
  final FossilService? fossilService;
  final Widget Function() tileLayerBuilder;

  static const double markerSize = 11.0;

  static Widget _defaultTileLayerBuilder() => const MapTileLayer();

  @override
  State<DinosaurCardFossilMap> createState() => _DinosaurCardFossilMapState();
}

class _DinosaurCardFossilMapState extends State<DinosaurCardFossilMap> {
  late final FossilService _service;
  late final bool _ownsService;

  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _loading = true;
  bool _error = false;
  List<FossilSummary> _geolocatedFossils = const [];

  @override
  void initState() {
    super.initState();
    _ownsService = widget.fossilService == null;
    _service = widget.fossilService ?? FossilService();
    _loadFossils();
  }

  @override
  void didUpdateWidget(covariant DinosaurCardFossilMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dinosaurId != widget.dinosaurId) {
      _loadFossils();
    }
  }

  Future<void> _loadFossils() async {
    setState(() {
      _loading = true;
      _error = false;
      _geolocatedFossils = const [];
    });

    try {
      final response =
          await _service.fetchFossilsForDinosaur(widget.dinosaurId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _geolocatedFossils = geolocatedFossils(response.items);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _panCameraToMarkers();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  void dispose() {
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  void _onMapReady() {
    if (!mounted) return;
    setState(() => _mapReady = true);
    _panCameraToMarkers();
  }

  void _panCameraToMarkers() {
    if (!_mapReady) return;

    _mapController.move(
      centerForFossils(_geolocatedFossils),
      MapConfig.minZoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    if (_loading) {
      return ColoredBox(
        color: cardTheme.cardBackground,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error) {
      return ColoredBox(
        color: cardTheme.cardBackground,
        child: Center(
          child: Text(
            'Could not load fossils',
            textAlign: TextAlign.center,
            style: cardTheme.bodyStyle(fontSize: 10),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: MapConfig.defaultCenter,
            initialZoom: MapConfig.minZoom,
            minZoom: MapConfig.minZoom,
            maxZoom: MapConfig.maxZoom,
            backgroundColor: cardTheme.cardBackground,
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(-85, -180),
                const LatLng(85, 180),
              ),
            ),
            onMapReady: _onMapReady,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            widget.tileLayerBuilder(),
            if (_geolocatedFossils.isNotEmpty)
              MarkerLayer(
                markers: _geolocatedFossils.map((fossil) {
                  return Marker(
                    point: LatLng(fossil.latitude!, fossil.longitude!),
                    width: DinosaurCardFossilMap.markerSize,
                    height: DinosaurCardFossilMap.markerSize,
                    child: GestureDetector(
                      onTap: () => showFossilMapCardDialog(context, fossil),
                      child: FossilMarker(
                        size: DinosaurCardFossilMap.markerSize,
                        selected: false,
                        showIcon: false,
                        color: cardTheme.cardAccent,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
        if (_geolocatedFossils.isEmpty)
          Center(
            child: Text(
              'No geolocated occurrences',
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10),
            ),
          ),
      ],
    );
  }
}

/// Fossils with valid modern coordinates.
List<FossilSummary> geolocatedFossils(List<FossilSummary> fossils) {
  return fossils
      .where((fossil) => fossil.latitude != null && fossil.longitude != null)
      .toList();
}

List<LatLng> latLngPointsForFossils(List<FossilSummary> fossils) {
  return geolocatedFossils(fossils)
      .map((fossil) => LatLng(fossil.latitude!, fossil.longitude!))
      .toList();
}

LatLngBounds? boundsForFossils(List<FossilSummary> fossils) {
  final points = latLngPointsForFossils(fossils);
  if (points.isEmpty) return null;
  if (points.length == 1) {
    final point = points.first;
    return LatLngBounds(point, point);
  }
  return LatLngBounds.fromPoints(points);
}

LatLng centerForFossils(List<FossilSummary> fossils) {
  final bounds = boundsForFossils(fossils);
  if (bounds == null) return MapConfig.defaultCenter;
  return bounds.center;
}
