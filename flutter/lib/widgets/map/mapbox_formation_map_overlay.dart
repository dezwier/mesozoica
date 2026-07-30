import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'formation_map_raster.dart';

const String formationMapSourceId = 'formation-map-source';
const String formationMapLayerId = 'formation-map-layer';

/// Mapbox ImageSource + RasterLayer for the Formation Map mosaic.
class MapboxFormationMapOverlay {
  MapboxMap? _map;
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
      developer.log('Formation map clear failed: $error', name: 'formation_map');
    }
  }

  Future<void> sync({
    required FormationMapRasterResult raster,
  }) async {
    final map = _map;
    if (map == null) return;
    final seq = ++_syncSeq;

    // Prefer isolate-preencoded PNG; fall back to UI-thread encode.
    final Uint8List pngBytes = raster.pngBytes ??
        await _rgbaToPng(
          raster.rgba,
          raster.width,
          raster.height,
        );
    if (seq != _syncSeq) return;

    final image = MbxImage(
      width: raster.width,
      height: raster.height,
      data: pngBytes,
    );
    final coords = raster.coordinates;

    try {
      final hasSource = await map.style.styleSourceExists(formationMapSourceId);
      if (seq != _syncSeq) return;

      if (!hasSource) {
        // Match Mapbox ImageSource example order: source → layer → image.
        await map.style.addSource(
          ImageSource(
            id: formationMapSourceId,
            coordinates: coords,
          ),
        );
        if (seq != _syncSeq) return;
        await _ensureLayer(map);
        if (seq != _syncSeq) return;
        await map.style.updateStyleImageSourceImage(
          formationMapSourceId,
          image,
        );
        developer.log(
          'Formation map installed '
          '${raster.width}x${raster.height} png=${pngBytes.length}B',
          name: 'formation_map',
        );
        return;
      }

      await map.style.setStyleSourceProperty(
        formationMapSourceId,
        'coordinates',
        coords,
      );
      if (seq != _syncSeq) return;
      await _ensureLayer(map);
      if (seq != _syncSeq) return;
      await map.style.updateStyleImageSourceImage(
        formationMapSourceId,
        image,
      );
    } catch (error, stack) {
      developer.log(
        'Formation map sync failed: $error\n$stack',
        name: 'formation_map',
      );
      if (kDebugMode) {
        debugPrint('Formation map sync failed: $error\n$stack');
      }
    }
  }

  Future<void> _ensureLayer(MapboxMap map) async {
    if (await map.style.styleLayerExists(formationMapLayerId)) return;
    // Standard style lightPreset dims custom rasters unless emissive strength
    // is raised (see mapbox_maps_flutter image_source_example.dart).
    await map.style.addLayer(
      RasterLayer(
        id: formationMapLayerId,
        sourceId: formationMapSourceId,
        slot: 'middle',
        rasterOpacity: 1.0,
        rasterFadeDuration: 0,
        // Keep some emissive so Standard lightPreset doesn't crush the
        // mosaic, but below 1.0 so period colors stay soft (not fluorescent).
        rasterEmissiveStrength: 0.65,
      ),
    );
  }

  static Future<Uint8List> _rgbaToPng(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('PNG encode failed for formation map raster');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void dispose() {
    _map = null;
  }
}
