/// Decode size for [CachedNetworkImage] `memCacheWidth` / `memCacheHeight`.
///
/// Keeps decoded bitmaps near on-screen size instead of full source resolution.
int networkImageMemCacheExtent(double logicalPx, double dpr) {
  if (!logicalPx.isFinite || logicalPx <= 0) {
    return (128 * dpr).round().clamp(1, 2048);
  }
  return (logicalPx * dpr).round().clamp(1, 2048);
}

/// Decode size that keeps the source aspect ratio.
///
/// Setting both cache axes forces the bitmap into the widget box and stretches
/// it. Only the longer side is constrained; [BoxFit.cover] crops the rest.
({int? width, int? height}) networkImageMemCacheBox({
  required double logicalWidth,
  required double logicalHeight,
  required double dpr,
}) {
  final width = networkImageMemCacheExtent(logicalWidth, dpr);
  final height = networkImageMemCacheExtent(logicalHeight, dpr);
  if (logicalWidth >= logicalHeight) {
    return (width: width, height: null);
  }
  return (width: null, height: height);
}
