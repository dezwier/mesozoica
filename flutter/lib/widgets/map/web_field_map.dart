import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesozoica/config/map_config.dart';
import 'package:mesozoica/controllers/aerial_session_controller.dart';
import 'package:mesozoica/controllers/formation_map_controller.dart';
import 'package:mesozoica/controllers/orbit_survey_controller.dart';
import 'package:mesozoica/models/site.dart';
import 'package:mesozoica/widgets/map/fossil_marker.dart';
import 'package:mesozoica/widgets/map/map_camera.dart';
import 'package:mesozoica/widgets/map/map_tile_layer.dart';
import 'package:mesozoica/widgets/map/period_marker_color.dart';

typedef MapSiteTapCallback = void Function(SiteSummary site);

/// Web field map using Carto/`flutter_map` (Mapbox Maps SDK has no v2 web renderer).
class MapboxFieldMap extends StatefulWidget {
  const MapboxFieldMap({
    super.key,
    required this.camera,
    required this.rotateWithHeading,
    required this.sites,
    required this.selectedSite,
    required this.markerDatasetKey,
    required this.currentLocation,
    required this.headingDeg,
    required this.followUser,
    required this.initialCenter,
    required this.initialZoom,
    required this.basemapTheme,
    required this.brightness,
    required this.onSiteTap,
    required this.onFollowCancelled,
    required this.onZoomChanged,
    required this.onReadyChanged,
    required this.onRotatePinchZoomOut,
    required this.onLocationPuckTap,
    this.mapActive = true,
    this.avatarImageUrl,
    this.rotateCardCount,
    this.headingListenable,
    this.locationListenable,
    this.aerialRecon,
    this.orbitSurvey,
    this.formationMap,
    this.disguisedSiteId,
    this.showPastAerialRoutes = true,
    this.showAerialReconOverlays = true,
    this.onError,
    this.onMapIdle,
  });

  final MapboxCameraCoordinator camera;
  final bool rotateWithHeading;
  final bool mapActive;
  final List<SiteSummary> sites;
  final SiteSummary? selectedSite;
  final String markerDatasetKey;
  final LatLng? currentLocation;
  final double headingDeg;
  final ValueListenable<double>? headingListenable;
  final ValueListenable<LatLng?>? locationListenable;
  final bool followUser;
  final LatLng initialCenter;
  final double initialZoom;
  final MapboxBasemapTheme basemapTheme;
  final Brightness brightness;
  final MapSiteTapCallback onSiteTap;
  final VoidCallback onFollowCancelled;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<bool> onReadyChanged;
  final VoidCallback onRotatePinchZoomOut;
  final VoidCallback onLocationPuckTap;
  final String? avatarImageUrl;
  final ValueNotifier<int>? rotateCardCount;
  final AerialSessionController? aerialRecon;
  final OrbitSurveyController? orbitSurvey;
  final FormationMapController? formationMap;
  final int? disguisedSiteId;
  final bool showPastAerialRoutes;
  final bool showAerialReconOverlays;
  final ValueChanged<Object>? onError;
  final VoidCallback? onMapIdle;

  @override
  State<MapboxFieldMap> createState() => _MapboxFieldMapState();
}

class _MapboxFieldMapState extends State<MapboxFieldMap> {
  final MapController _mapController = MapController();
  bool _readyNotified = false;

  @override
  void initState() {
    super.initState();
    widget.camera.bindFlutterMap(_mapController);
    widget.camera.rotateWithHeading = widget.rotateWithHeading;
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyReady());
  }

  @override
  void didUpdateWidget(covariant MapboxFieldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.camera.rotateWithHeading = widget.rotateWithHeading;
    if (oldWidget.camera != widget.camera) {
      oldWidget.camera.detach();
      widget.camera.bindFlutterMap(_mapController);
    }
  }

  @override
  void dispose() {
    widget.camera.detach();
    super.dispose();
  }

  void _notifyReady() {
    if (!mounted || _readyNotified) return;
    _readyNotified = true;
    widget.onReadyChanged(true);
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.locationListenable?.value ?? widget.currentLocation;
    final selectedId = widget.selectedSite?.siteId;
    final markers = <Marker>[
      for (final site in widget.sites)
        if (site.latitude != null && site.longitude != null)
          Marker(
            point: LatLng(site.latitude!, site.longitude!),
            width: 18,
            height: 18,
            child: GestureDetector(
              onTap: () => widget.onSiteTap(site),
              child: FossilMarker(
                size: 16,
                selected: site.siteId == selectedId,
                showIcon: false,
                color: periodMarkerColor(site.effectivePeriod),
              ),
            ),
          ),
      if (location != null)
        Marker(
          point: location,
          width: 28,
          height: 28,
          child: GestureDetector(
            onTap: widget.onLocationPuckTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF8D6E63),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        widget.camera.setViewportSize(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
        );
        return FlutterMap(
          key: ValueKey(widget.markerDatasetKey),
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            minZoom: MapConfig.minZoom,
            maxZoom: MapConfig.maxZoom,
            interactiveFlags: widget.mapActive
                ? InteractiveFlag.all
                : InteractiveFlag.none,
            onMapReady: _notifyReady,
            onPositionChanged: (camera, hasGesture) {
              final zoom = camera.zoom;
              if (zoom != null) widget.onZoomChanged(zoom);
              if (hasGesture) widget.onFollowCancelled();
              widget.onMapIdle?.call();
            },
          ),
          children: [
            const MapTileLayer(),
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }
}
