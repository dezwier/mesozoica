import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../widgets/map/mapbox_aerial_annotations.dart';
import '../../../../widgets/map/mapbox_site_annotations.dart';
import '../../../../models/site.dart';

/// Owns Mapbox annotation-manager creation order and attachment lifecycle.
class MapboxAnnotationBundle {
  MapboxAnnotationBundle({required this.onSiteTap, required this.onScoutTap});

  final void Function(SiteSummary site) onSiteTap;
  final void Function(int sessionId) onScoutTap;

  MapboxSiteAnnotations? site;
  MapboxAerialAnnotations? aerial;

  Future<void> attach(MapboxMap map) async {
    // Paint order is contract-sensitive: shadow → rim → fill → highlight → selection.
    final shadowManager = await map.annotations.createCircleAnnotationManager();
    final rimManager = await map.annotations.createCircleAnnotationManager();
    final manager = await map.annotations.createCircleAnnotationManager();
    final highlightManager = await map.annotations
        .createCircleAnnotationManager();
    final selectionDotManager = await map.annotations
        .createCircleAnnotationManager();
    final nextSite = MapboxSiteAnnotations(onSiteTap: onSiteTap);
    await nextSite.attach(
      shadowManager: shadowManager,
      rimManager: rimManager,
      manager: manager,
      highlightManager: highlightManager,
      selectionDotManager: selectionDotManager,
    );

    final lineManager = await map.annotations.createPolylineAnnotationManager();
    final scoutManager = await map.annotations.createPointAnnotationManager();
    final nextAerial = MapboxAerialAnnotations();
    await nextAerial.attach(
      lineManager: lineManager,
      scoutManager: scoutManager,
      onScoutTap: onScoutTap,
    );

    site?.dispose();
    aerial?.dispose();
    site = nextSite;
    aerial = nextAerial;
  }

  void dispose() {
    site?.dispose();
    aerial?.dispose();
    site = null;
    aerial = null;
  }
}
