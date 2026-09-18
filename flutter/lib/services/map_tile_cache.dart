import 'dart:io';

import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:path_provider/path_provider.dart';

/// Disk-backed cache for Carto map tiles (shared by main map and card mini maps).
class MapTileCache {
  MapTileCache._();

  static const Duration _maxStale = Duration(days: 30);

  static CachedTileProvider? _provider;

  static Future<void> initialize() async {
    if (_provider != null) return;

    final cacheDir = await getApplicationCacheDirectory();
    final store = FileCacheStore(
      '${cacheDir.path}${Platform.pathSeparator}map_tiles',
    );

    _provider = CachedTileProvider(
      store: store,
      cachePolicy: CachePolicy.request,
      maxStale: _maxStale,
    );
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
