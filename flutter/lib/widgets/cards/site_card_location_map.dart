import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../controllers/map_controller.dart';
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

  void _openOnMap(BuildContext context) {
    final point = _sitePoint(site);
    if (point == null) return;

    // AppShell watches MapController and closes overlays when a focus
    // request is pending (works from root-navigator card dialogs).
    context.read<MapController>().requestFocusOnSite(site);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = _sitePoint(site);

    return CardWorldMap(
      markers: point == null ? const [] : [CardMapMarker(point: point)],
      center: point ?? MapConfig.defaultCenter,
      zoom: MapConfig.siteCardMapZoom,
      interactive: false,
      onTap: point == null ? null : () => _openOnMap(context),
      emptyMessage: 'No location',
      tileLayerBuilder: tileLayerBuilder,
    );
  }
}

LatLng? _sitePoint(SiteSummary site) {
  if (site.latitude == null || site.longitude == null) return null;
  return LatLng(site.latitude!, site.longitude!);
}
