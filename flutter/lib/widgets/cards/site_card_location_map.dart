import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../config/map_config.dart';
import '../../models/site.dart';
import 'card_world_map.dart';

/// Site location marker on the site card back world map.
class SiteCardLocationMap extends StatelessWidget {
  const SiteCardLocationMap({
    super.key,
    required this.site,
    this.tileLayerBuilder = CardWorldMap.defaultTileLayerBuilder,
  });

  final SiteSummary site;
  final Widget Function() tileLayerBuilder;

  @override
  Widget build(BuildContext context) {
    final point = _sitePoint(site);

    return CardWorldMap(
      markers: point == null
          ? const []
          : [CardMapMarker(point: point)],
      center: point ?? MapConfig.defaultCenter,
      emptyMessage: 'No location',
      tileLayerBuilder: tileLayerBuilder,
    );
  }
}

LatLng? _sitePoint(SiteSummary site) {
  if (site.latitude == null || site.longitude == null) return null;
  return LatLng(site.latitude!, site.longitude!);
}
