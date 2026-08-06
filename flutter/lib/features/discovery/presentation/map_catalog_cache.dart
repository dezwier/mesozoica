import 'package:flutter_map/flutter_map.dart';

import '../../../models/site.dart';

/// Separate map caches so archive / field-linked / field-show-all switch
/// instantly without reloading another dataset.
enum MapCacheKey { archive, fieldLinked, fieldShowAll }

/// Mutable pagination state for one map catalog dataset.
///
/// Ownership is intentionally separate from [MapController] so cache policy
/// can be characterized without involving selection, polling, or widgets.
class MapCatalogSnapshot {
  List<SiteSummary> geoSites = [];
  bool loading = false;
  bool loadingComplete = false;
  String? error;
  LatLngBounds? siteBounds;
  int offset = 0;
  int totalCatalog = 0;
  int loadedCatalog = 0;
  int maxFieldSiteId = 0;
  String? seed;
  int loadSeq = 0;
  DateTime? loadedAt;
  bool replaceOnNextPage = false;

  void reset({required bool clearSeed}) {
    geoSites = [];
    siteBounds = null;
    offset = 0;
    loadedCatalog = 0;
    totalCatalog = 0;
    loadingComplete = false;
    loading = false;
    error = null;
    maxFieldSiteId = 0;
    loadedAt = null;
    replaceOnNextPage = false;
    if (clearSeed) seed = null;
  }
}
