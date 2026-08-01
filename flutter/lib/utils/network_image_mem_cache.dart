/// Decode size for [CachedNetworkImage] `memCacheWidth` / `memCacheHeight`.
///
/// Keeps decoded bitmaps near on-screen size instead of full source resolution.
int networkImageMemCacheExtent(double logicalPx, double dpr) {
  if (!logicalPx.isFinite || logicalPx <= 0) {
    return (128 * dpr).round().clamp(1, 2048);
  }
  return (logicalPx * dpr).round().clamp(1, 2048);
}
