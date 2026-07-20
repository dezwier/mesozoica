import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/site.dart';
import 'fossil_marker.dart';
import 'map_visible_bounds.dart';
import 'period_marker_color.dart';

class SiteMarkersLayer extends StatelessWidget {
  const SiteMarkersLayer({
    super.key,
    required this.sites,
    required this.mapReady,
    required this.selectedSite,
    required this.onSiteTap,
  });

  final List<SiteSummary> sites;
  final bool mapReady;
  final SiteSummary? selectedSite;
  final ValueChanged<SiteSummary> onSiteTap;

  @override
  Widget build(BuildContext context) {
    if (!mapReady) return const SizedBox.shrink();

    final map = MapCamera.of(context);
    final zoomLevel = map.zoom;
    final showIcon = fossilMarkerShowsIcon(zoomLevel);
    final bounds = paddedVisibleBounds(map.visibleBounds);
    final baseSize = fossilMarkerSizeForZoom(zoomLevel, selected: false);
    // Marker slot always fits the expanded size so scale animates in place.
    final slotSize = baseSize * 2;

    final visibleSites = sites.where((site) {
      final point = LatLng(site.latitude!, site.longitude!);
      return bounds.contains(point);
    });

    return MarkerLayer(
      markers: visibleSites.map((site) {
        final selected = selectedSite?.siteId == site.siteId;
        final color = periodMarkerColor(site.effectivePeriod);

        return Marker(
          point: LatLng(site.latitude!, site.longitude!),
          width: slotSize,
          height: slotSize,
          child: GestureDetector(
            key: ValueKey(site.siteId),
            onTap: () => onSiteTap(site),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: AnimatedScale(
                scale: selected ? 2.0 : 1.0,
                duration: FossilMarker.selectionDuration,
                curve: FossilMarker.selectionCurve,
                child: FossilMarker(
                  size: baseSize,
                  selected: selected,
                  showIcon: showIcon,
                  color: color,
                  animateSelection: true,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
