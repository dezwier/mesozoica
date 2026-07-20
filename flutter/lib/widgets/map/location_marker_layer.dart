import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/map_config.dart';
import 'period_marker_color.dart';

/// User GPS / heading arrow. Drawn above site markers.
class LocationMarkerLayer extends StatelessWidget {
  const LocationMarkerLayer({
    super.key,
    required this.currentLocation,
    required this.headingDeg,
    required this.rotateMap,
    required this.mapReady,
  });

  final LatLng? currentLocation;
  final double headingDeg;
  final bool rotateMap;
  final bool mapReady;

  @override
  Widget build(BuildContext context) {
    if (currentLocation == null) return const SizedBox.shrink();

    final primary = mapMarkerPrimaryColor();

    return MarkerLayer(
      rotate: false,
      markers: [
        if (!rotateMap)
          Marker(
            point: currentLocation!,
            width: MapConfig.markerSize,
            height: MapConfig.markerSize,
            child: Transform.rotate(
              angle: (headingDeg - 180) * math.pi / 360,
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: (headingDeg + 180) * math.pi / 360,
                child: Icon(
                  Icons.navigation,
                  size: MapConfig.markerIconSize,
                  color: primary,
                ),
              ),
            ),
          ),
        if (rotateMap && mapReady)
          Marker(
            point: currentLocation!,
            width: MapConfig.markerSize,
            height: MapConfig.markerSize,
            child: Transform.rotate(
              angle: headingDeg * math.pi / 180,
              alignment: Alignment.center,
              child: Icon(
                Icons.navigation,
                size: MapConfig.markerIconSize,
                color: primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// Camera-center crosshair. Drawn below site markers so sites stay tappable.
class MapCenterMarkerLayer extends StatelessWidget {
  const MapCenterMarkerLayer({
    super.key,
    required this.currentLocation,
    required this.mapReady,
  });

  final LatLng? currentLocation;
  final bool mapReady;

  static const _centeredThresholdMeters = 50;

  bool _isCenteredOnCurrent(LatLng? current, LatLng cameraCenter) {
    if (current == null) return true;
    const distance = Distance();
    return distance(cameraCenter, current) < _centeredThresholdMeters;
  }

  @override
  Widget build(BuildContext context) {
    if (!mapReady || currentLocation == null) {
      return const SizedBox.shrink();
    }

    final cameraCenter = MapCamera.of(context).center;
    if (_isCenteredOnCurrent(currentLocation, cameraCenter)) {
      return const SizedBox.shrink();
    }

    final primary = mapMarkerPrimaryColor();

    return MarkerLayer(
      rotate: false,
      markers: [
        Marker(
          point: cameraCenter,
          width: MapConfig.markerSize,
          height: MapConfig.markerSize,
          child: SizedBox(
            width: 60,
            height: 60,
            child: Icon(
              Icons.my_location,
              size: MapConfig.markerIconSize,
              color: primary,
            ),
          ),
        ),
      ],
    );
  }
}
