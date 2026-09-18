import 'package:flutter_map/flutter_map.dart';

import 'map_tile_cache_web.dart'
    if (dart.library.io) 'map_tile_cache_io.dart'
    as impl;

/// Tile provider for Carto basemaps (disk cache on IO, network on web).
class MapTileCache {
  MapTileCache._();

  static TileProvider? _provider;

  static Future<void> initialize() async {
    _provider ??= await impl.createMapTileProvider();
  }

  static TileProvider get tileProvider {
    final provider = _provider;
    if (provider == null) {
      throw StateError(
        'MapTileCache.initialize() must complete before using tileProvider',
      );
    }
    return provider;
  }
}
