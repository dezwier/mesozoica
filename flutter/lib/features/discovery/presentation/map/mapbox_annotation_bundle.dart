import 'package:flutter/foundation.dart';
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

    // Site markers are the primary map layer. Publish them as soon as their
    // managers are ready so an optional expedition-overlay failure cannot
    // leave a populated map with no site markers.
    site?.dispose();
    site = nextSite;

    try {
      final lineManager = await map.annotations
          .createPolylineAnnotationManager();
      final scoutManager = await map.annotations.createPointAnnotationManager();
      final nextAerial = MapboxAerialAnnotations();
      await nextAerial.attach(
        lineManager: lineManager,
        scoutManager: scoutManager,
        onScoutTap: onScoutTap,
      );
      aerial?.dispose();
      aerial = nextAerial;
    } catch (error, stack) {
      // Aerial recon is optional. Keep the successfully attached site layer
      // alive and let the map continue through gesture setup and marker sync.
      aerial?.dispose();
      aerial = null;
      if (kDebugMode) {
        debugPrint('Mapbox aerial annotation setup failed: $error\n$stack');
      }
    }
  }

  void dispose() {
    site?.dispose();
    aerial?.dispose();
    site = null;
    aerial = null;
  }
}
