/// Monotonic counters for the admin map perf HUD.
///
/// Deliberately a plain static counter rather than a [ChangeNotifier]: these
/// increment on hot paths (per projection, per platform-channel call), so
/// notifying listeners would cost more than the work being measured. The HUD
/// diffs them over its own ~2 Hz sampling window.
class MapPerfCounters {
  MapPerfCounters._();

  /// Rotate / detail-pin overlay projections that actually ran.
  static int overlayProjections = 0;

  /// Mapbox platform-channel round-trips issued from Dart map code.
  static int mapboxChannelCalls = 0;

  static void countOverlayProjection() {
    overlayProjections++;
    mapboxChannelCalls++;
  }

  static void countChannelCall() {
    mapboxChannelCalls++;
  }
}
