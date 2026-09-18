import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:path_provider/path_provider.dart';

Future<TileProvider> createMapTileProvider() async {
  final cacheDir = await getApplicationCacheDirectory();
  return CachedTileProvider(
    store: FileCacheStore('${cacheDir.path}/map_tiles'),
    cachePolicy: CachePolicy.request,
    maxStale: const Duration(days: 30),
  );
}
