import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/map_config.dart';
import '../../theme/dino_card_theme.dart';
import '../map/fossil_marker.dart';
import '../map/map_tile_layer.dart';

class CardMapMarker {
  const CardMapMarker({
    required this.point,
    this.onTap,
  });

  final LatLng point;
  final VoidCallback? onTap;
}

/// Shared mini world map for card backs — max zoom-out with optional auto-pan.
class CardWorldMap extends StatefulWidget {
  const CardWorldMap({
    super.key,
    required this.markers,
    required this.center,
    this.emptyMessage = 'No geolocated occurrences',
    this.tileLayerBuilder = CardWorldMap.defaultTileLayerBuilder,
  });

  final List<CardMapMarker> markers;
  final LatLng center;
  final String emptyMessage;
  final Widget Function() tileLayerBuilder;

  static const double markerSize = 11.0;

  static Widget defaultTileLayerBuilder() => const MapTileLayer();

  @override
  State<CardWorldMap> createState() => _CardWorldMapState();
}

class _CardWorldMapState extends State<CardWorldMap> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  @override
  void didUpdateWidget(covariant CardWorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center != widget.center ||
        oldWidget.markers.length != widget.markers.length) {
      _panCamera();
    }
  }

  void _onMapReady() {
    if (!mounted) return;
    setState(() => _mapReady = true);
    _panCamera();
  }

  void _panCamera() {
    if (!_mapReady) return;
    _mapController.move(widget.center, MapConfig.minZoom);
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.center,
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
            if (widget.markers.isNotEmpty)
              MarkerLayer(
                markers: widget.markers.map((marker) {
                  return Marker(
                    point: marker.point,
                    width: CardWorldMap.markerSize,
                    height: CardWorldMap.markerSize,
                    child: GestureDetector(
                      onTap: marker.onTap,
                      child: FossilMarker(
                        size: CardWorldMap.markerSize,
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
        if (widget.markers.isEmpty)
          Center(
            child: Text(
              widget.emptyMessage,
              textAlign: TextAlign.center,
              style: cardTheme.bodyStyle(fontSize: 10),
            ),
          ),
      ],
    );
  }
}
