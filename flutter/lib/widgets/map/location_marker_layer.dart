import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/map_config.dart';

class LocationMarkerLayer extends StatelessWidget {
  const LocationMarkerLayer({
    super.key,
    required this.currentLocation,
    required this.headingDeg,
    required this.rotateMap,
    required this.mapReady,
    this.onTapCenter,
  });

  final LatLng? currentLocation;
  final double headingDeg;
  final bool rotateMap;
  final bool mapReady;
  final VoidCallback? onTapCenter;

  static const _centeredThresholdMeters = 50;

  bool _isCenteredOnCurrent(LatLng? current, LatLng cameraCenter) {
    if (current == null) return true;
    const distance = Distance();
    return distance(cameraCenter, current) < _centeredThresholdMeters;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final cameraCenter = MapCamera.of(context).center;
    final isCenteredOnCurrent =
        _isCenteredOnCurrent(currentLocation, cameraCenter);

    return MarkerLayer(
      rotate: false,
      markers: [
        if (currentLocation != null && !rotateMap)
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
        if (currentLocation != null && rotateMap && mapReady)
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
        if (mapReady && currentLocation != null && !isCenteredOnCurrent)
          Marker(
            point: cameraCenter,
            width: MapConfig.markerSize,
            height: MapConfig.markerSize,
            child: GestureDetector(
              onTap: onTapCenter,
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
          ),
      ],
    );
  }
}
