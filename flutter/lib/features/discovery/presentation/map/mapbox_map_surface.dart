import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:mesozoica/controllers/terrain_echo_controller.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/theme/map_chrome_theme.dart';
import 'package:mesozoica/widgets/map/map_center_crosshair.dart';
import 'package:mesozoica/widgets/map/map_rotate_site_card_overlay.dart';
import 'package:mesozoica/widgets/map/mapbox_camera_coordinator.dart';
import 'package:mesozoica/widgets/map/ridge_glass_pulse_overlay.dart';
import 'package:mesozoica/widgets/map/terrain_echo_overlay.dart';
import 'package:provider/provider.dart';

import 'rotate_pinch_zoom_out_listener.dart';

/// Focused visual surface for the Mapbox adapter.
///
/// Map lifecycle and reconciliation remain in the stateful adapter; this
/// widget only lays out the native map and Flutter overlays in their original
/// paint order.
class MapboxMapSurface extends StatelessWidget {
  const MapboxMapSurface({
    super.key,
    required this.tokenReady,
    required this.ready,
    required this.mapActive,
    required this.rotateWithHeading,
    required this.followUser,
    required this.detailPinsActive,
    required this.ridgeGlassPulseActive,
    required this.camera,
    required this.viewport,
    required this.lastKnownZoom,
    required this.visibleRotateSites,
    required this.selectedSite,
    required this.disguisedSiteId,
    required this.onLayout,
    required this.onMapCreated,
    required this.onStyleLoaded,
    required this.onMapLoaded,
    required this.onMapTap,
    required this.onScroll,
    required this.onCameraChange,
    required this.onMapIdle,
    required this.onMapLoadError,
    required this.onRotateSiteTap,
    required this.onRotatePinchZoomOut,
    required this.baseVisibilityM,
    required this.fullVisibilityM,
  });

  final bool tokenReady;
  final bool ready;
  final bool mapActive;
  final bool rotateWithHeading;
  final bool followUser;
  final bool detailPinsActive;
  final bool ridgeGlassPulseActive;
  final MapboxCameraCoordinator camera;
  final ViewportState viewport;
  final double lastKnownZoom;
  final List<MapRotateVisibleSite> visibleRotateSites;
  final SiteSummary? selectedSite;
  final int? disguisedSiteId;
  final void Function(double width, double height) onLayout;
  final Future<void> Function(MapboxMap map) onMapCreated;
  final void Function(StyleLoadedEventData data) onStyleLoaded;
  final void Function(MapLoadedEventData data) onMapLoaded;
  final void Function(MapContentGestureContext context) onMapTap;
  final void Function(MapContentGestureContext context) onScroll;
  final void Function(CameraChangedEventData data) onCameraChange;
  final void Function(MapIdleEventData data) onMapIdle;
  final ValueChanged<String> onMapLoadError;
  final ValueChanged<SiteSummary> onRotateSiteTap;
  final VoidCallback onRotatePinchZoomOut;
  final double baseVisibilityM;
  final double fullVisibilityM;

  @override
  Widget build(BuildContext context) {
    if (!tokenReady) {
      return const ColoredBox(
        color: Color(0xFFE8DFD4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 12),
              Text('Preparing Mapbox…'),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        if (height.isFinite && height > 0 && width.isFinite && width > 0) {
          onLayout(width, height);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            MapWidget(
              key: const ValueKey('mapbox_field_map'),
              styleUri: MapboxStyles.STANDARD,
              viewport: viewport,
              onMapCreated: onMapCreated,
              onStyleLoadedListener: onStyleLoaded,
              onMapLoadedListener: onMapLoaded,
              onTapListener: onMapTap,
              onScrollListener: onScroll,
              onCameraChangeListener: onCameraChange,
              onMapIdleListener: onMapIdle,
              onMapLoadErrorListener: (event) => onMapLoadError(event.message),
            ),
            const IgnorePointer(
              child: ColoredBox(color: MapChromeTheme.mapSandstoneWash),
            ),
            if (mapActive && ready)
              Consumer<TerrainEchoController>(
                builder: (context, echo, _) {
                  if (!echo.isActive) return const SizedBox.shrink();
                  return TerrainEchoOverlay(
                    camera: camera,
                    rotateWithHeading: rotateWithHeading,
                    zoom: lastKnownZoom,
                  );
                },
              ),
            if (mapActive && ready && ridgeGlassPulseActive)
              RidgeGlassPulseOverlay(
                camera: camera,
                baseVisibilityM: baseVisibilityM,
                fullVisibilityM: fullVisibilityM,
                rotateWithHeading: rotateWithHeading,
                zoom: lastKnownZoom,
              ),
            if (mapActive && !rotateWithHeading && !followUser && ready)
              const MapCenterCrosshair(),
            if (mapActive && (rotateWithHeading || detailPinsActive) && ready)
              Positioned.fill(
                child: MapRotateSiteCardOverlay(
                  visibleSites: visibleRotateSites,
                  selectedSiteId: selectedSite?.siteId,
                  disguisedSiteId: disguisedSiteId,
                  onSiteTap: onRotateSiteTap,
                ),
              ),
            if (mapActive && rotateWithHeading && ready)
              Positioned.fill(
                child: RotatePinchZoomOutListener(
                  onZoomOut: onRotatePinchZoomOut,
                ),
              ),
            if (!ready)
              Positioned(
                left: 16,
                right: 16,
                bottom: 160,
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Expanded(child: Text('Loading map tiles…')),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
