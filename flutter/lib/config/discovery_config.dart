/// Timings for the site-discovery celebration card flips.
///
/// Sequence: scale in → wait → flip to back (map) → settle → hold on back →
/// flip to front.
class DiscoveryConfig {
  DiscoveryConfig._();

  /// Scale-in animation when the celebration sheet appears.
  static const Duration celebrationScaleIn = Duration(milliseconds: 520);

  /// Pause after the card appears, before the first auto-flip to the back.
  static const Duration autoFlipStartDelay = Duration(milliseconds: 450);

  /// Approximate time for the spring flip animation to settle on a face.
  static const Duration autoFlipSettle = Duration(milliseconds: 400);

  /// How long the card stays on the back (map) before flipping to the front.
  static const Duration autoFlipHoldOnBack = Duration(milliseconds: 400);
}
