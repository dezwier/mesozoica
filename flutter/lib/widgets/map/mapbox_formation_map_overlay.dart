import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../utils/formation_map_raster.dart';

const String formationMapSourceId = 'formation-map-source';
const String formationMapLayerId = 'formation-map-layer';

/// Mapbox ImageSource + RasterLayer for the Formation Map mosaic.
class MapboxFormationMapOverlay {
  MapboxMap? _map;
  bool _installed = false;
  int _syncSeq = 0;

  void attach(MapboxMap map) {
    _map = map;
  }

  Future<void> clear() async {
    _syncSeq++;
    final map = _map;
    if (map == null) return;
    try {
      if (await map.style.styleLayerExists(formationMapLayerId)) {
        await map.style.removeStyleLayer(formationMapLayerId);
      }
      if (await map.style.styleSourceExists(formationMapSourceId)) {
        await map.style.removeStyleSource(formationMapSourceId);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Formation map clear failed: $error');
      }
    }
    _installed = false;
  }

  Future<void> sync({
    required FormationMapRasterResult raster,
  }) async {
    final map = _map;
    if (map == null) return;
    final seq = ++_syncSeq;
    final image = MbxImage(
      width: raster.width,
      height: raster.height,
      data: Uint8List.fromList(raster.rgbaPremultiplied),
    );
    final coords = raster.coordinates;

    try {
      final hasSource = await map.style.styleSourceExists(formationMapSourceId);
      if (seq != _syncSeq) return;

      if (!hasSource) {
        await map.style.addSource(
          ImageSource(
            id: formationMapSourceId,
            coordinates: coords,
          ),
        );
        if (seq != _syncSeq) return;
        final source = await map.style.getSource(formationMapSourceId);
        if (source is ImageSource) {
          await source.updateImage(image);
        }
        if (seq != _syncSeq) return;
        final hasLayer = await map.style.styleLayerExists(formationMapLayerId);
        if (!hasLayer) {
          await map.style.addLayer(
            RasterLayer(
              id: formationMapLayerId,
              sourceId: formationMapSourceId,
              rasterOpacity: 1.0,
              rasterFadeDuration: 0,
            ),
          );
        }
        _installed = true;
        return;
      }

      await map.style.setStyleSourceProperty(
        formationMapSourceId,
        'coordinates',
        coords,
      );
      if (seq != _syncSeq) return;
      final source = await map.style.getSource(formationMapSourceId);
      if (source is ImageSource) {
        await source.updateImage(image);
      }
      if (!_installed) {
        final hasLayer = await map.style.styleLayerExists(formationMapLayerId);
        if (!hasLayer) {
          await map.style.addLayer(
            RasterLayer(
              id: formationMapLayerId,
              sourceId: formationMapSourceId,
              rasterOpacity: 1.0,
              rasterFadeDuration: 0,
            ),
          );
        }
        _installed = true;
      }
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Formation map sync failed: $error\n$stack');
      }
    }
  }

  void dispose() {
    _map = null;
    _installed = false;
  }
}
