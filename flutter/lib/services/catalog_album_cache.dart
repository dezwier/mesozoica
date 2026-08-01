import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for catalog album WebP thumbs.
///
/// Isolated from [DefaultCacheManager] so full card PNGs (Cover Flow / dialogs)
/// do not evict the small album tiles. Content is already busted via `?v=`.
class CatalogAlbumCache {
  CatalogAlbumCache._();

  static const String key = 'catalogAlbumImages';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 800,
    ),
  );
}
