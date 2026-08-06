import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/map_config.dart';
import '../../theme/dino_card_theme.dart';
import '../map/fossil_marker.dart';
import '../map/map_tile_layer.dart';

class CardMapMarker {
  const CardMapMarker({required this.point, this.onTap, this.opacity = 1.0});

  final LatLng point;
  final VoidCallback? onTap;
  final double opacity;
}

/// Shared mini world map for card backs — optional auto-pan and interaction.
class CardWorldMap extends StatefulWidget {
  const CardWorldMap({
    super.key,
    required this.markers,
    required this.center,
    this.zoom = MapConfig.cardMapZoom,
    this.interactive = true,
    this.onTap,
    this.emptyMessage = 'No geolocated occurrences',
    this.tileLayerBuilder = CardWorldMap.defaultTileLayerBuilder,
  });

  final List<CardMapMarker> markers;
  final LatLng center;
  final double zoom;

  /// When false, the map behaves like a static image (no pan/zoom).
  final bool interactive;
  final VoidCallback? onTap;
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
        oldWidget.zoom != widget.zoom ||
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
    _mapController.move(widget.center, widget.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme = DinoCardTheme.of(context);
    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.zoom,
        minZoom: widget.zoom,
        maxZoom: widget.interactive ? MapConfig.maxZoom : widget.zoom,
        backgroundColor: cardTheme.cardBackground,
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(const LatLng(-85, -180), const LatLng(85, 180)),
        ),
        onMapReady: _onMapReady,
        onTap: widget.onTap == null ? null : (_, _) => widget.onTap!(),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.flingAnimation
              : InteractiveFlag.none,
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
                  onTap: marker.onTap ?? widget.onTap,
                  child: Opacity(
                    opacity: marker.opacity,
                    child: FossilMarker(
                      size: CardWorldMap.markerSize,
                      selected: false,
                      showIcon: false,
                      color: cardTheme.cardAccent,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Non-interactive maps still need a hit target for [onTap]; flutter_map
        // may not deliver taps when all interaction flags are off.
        if (!widget.interactive && widget.onTap != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AbsorbPointer(child: map),
          )
        else
          map,
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
