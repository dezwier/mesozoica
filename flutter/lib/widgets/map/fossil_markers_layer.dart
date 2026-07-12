import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/fossil.dart';
import 'fossil_marker.dart';

class FossilMarkersLayer extends StatelessWidget {
  const FossilMarkersLayer({
    super.key,
    required this.fossils,
    required this.zoomLevel,
    required this.mapReady,
    required this.visibleBounds,
    required this.selectedFossil,
    required this.onFossilTap,
  });

  final List<FossilSummary> fossils;
  final double zoomLevel;
  final bool mapReady;
  final LatLngBounds? visibleBounds;
  final FossilSummary? selectedFossil;
  final ValueChanged<FossilSummary> onFossilTap;

  @override
  Widget build(BuildContext context) {
    if (!mapReady) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.primary;
    final showIcon = fossilMarkerShowsIcon(zoomLevel);
    final bounds = visibleBounds;

    final visibleFossils = bounds == null
        ? fossils
        : fossils.where((fossil) {
            final point = LatLng(fossil.latitude!, fossil.longitude!);
            return bounds.contains(point);
          });

    return MarkerLayer(
      markers: visibleFossils.map((fossil) {
        final selected = selectedFossil?.id == fossil.id;
        final size = fossilMarkerSizeForZoom(zoomLevel, selected: selected);

        return Marker(
          point: LatLng(fossil.latitude!, fossil.longitude!),
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () => onFossilTap(fossil),
            child: FossilMarker(
              size: size,
              selected: selected,
              showIcon: showIcon,
              color: color,
            ),
          ),
        );
      }).toList(),
    );
  }
}
