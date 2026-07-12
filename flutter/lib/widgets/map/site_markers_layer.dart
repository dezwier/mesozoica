import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/site.dart';
import 'fossil_marker.dart';
import 'period_marker_color.dart';

class SiteMarkersLayer extends StatelessWidget {
  const SiteMarkersLayer({
    super.key,
    required this.sites,
    required this.zoomLevel,
    required this.mapReady,
    required this.visibleBounds,
    required this.selectedSite,
    required this.onSiteTap,
  });

  final List<SiteSummary> sites;
  final double zoomLevel;
  final bool mapReady;
  final LatLngBounds? visibleBounds;
  final SiteSummary? selectedSite;
  final ValueChanged<SiteSummary> onSiteTap;

  @override
  Widget build(BuildContext context) {
    if (!mapReady) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final showIcon = fossilMarkerShowsIcon(zoomLevel);
    final bounds = visibleBounds;

    final visibleSites = bounds == null
        ? sites
        : sites.where((site) {
            final point = LatLng(site.latitude!, site.longitude!);
            return bounds.contains(point);
          });

    return MarkerLayer(
      markers: visibleSites.map((site) {
        final selected = selectedSite?.siteId == site.siteId;
        final size = fossilMarkerSizeForZoom(zoomLevel, selected: selected);
        final color = periodMarkerColor(site.effectivePeriod, scheme);

        return Marker(
          point: LatLng(site.latitude!, site.longitude!),
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () => onSiteTap(site),
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
