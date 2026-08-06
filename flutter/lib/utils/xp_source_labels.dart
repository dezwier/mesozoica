/// XP source labels and presentation routing.
///
/// **Rule:** every skill XP award the client announces is shown in exactly one
/// of two ways — never both, never neither (when `announceXp` is true):
///
/// 1. **Celebration** (big events) — XP is embedded in the celebration plaque
///    (title + skill avatar + source + amount). All XP from that event is shown
///    there (e.g. site discovery + first-discovery bonus on the same plaque).
/// 2. **XP badge** (small / ongoing events) — floating overlay chip under the
///    profile HUD ([XpAwardOverlay]).
///
/// Classification is by skill_breakdown key ([kCelebrationXpSourceKeys] vs
/// everything else). Unknown / remainder fallbacks use a badge.
library xp_source_labels;

import '../config/game_config.dart';

/// Human labels for skill_breakdown keys (XP sources / main_param awards).
///
/// Distance keys use a 100 m placeholder; prefer [xpSourceLabelForAward] when
/// the XP amount (or meters) is known so the badge shows the real distance.
const kXpBreakdownLabels = <String, String>{
  'discover_site': 'Discover site',
  'locate_fossil_in_situ': 'Locate fossil in situ',
  'explore_100m_actively': 'Explore 100m actively',
  'explore_100m_passively': 'Explore 100m passively',
  'disguise_of_site': 'Disguise of site',
  'document_progress': 'Document progress',
  'document_site': 'Document site',
  'identify_site': 'Identify site',
  'discover_site_as_first': 'Discover site as first',
  'document_site_as_first': 'Document site as first',
};

/// Breakdown keys for **big-event celebrations** (embedded in the plaque).
///
/// Not shown as floating XP badges. See library doc on this file.
const kCelebrationXpSourceKeys = <String>{
  'discover_site',
  'discover_site_as_first',
  'locate_fossil_in_situ',
  'document_site',
  'document_site_as_first',
  'identify_site',
};

/// Keys claimed by the site-discovered celebration.
const kSiteDiscoveryCelebrationXpKeys = <String>{
  'discover_site',
  'discover_site_as_first',
  'locate_fossil_in_situ',
};

/// Keys claimed by fossil discovery celebrations (none — locate XP is on the
/// site discovery plaque).
const kFossilDiscoveryCelebrationXpKeys = <String>{};

/// Keys claimed by the site-documented celebration.
const kSiteDocumentationCelebrationXpKeys = <String>{
  'document_site',
  'document_site_as_first',
};

/// Keys claimed by the site-identified celebration.
const kSiteIdentificationCelebrationXpKeys = <String>{'identify_site'};

/// True → celebrate (embed XP); false → floating XP badge.
///
/// Empty / null keys are badge fallbacks (skill-name remainder awards).
bool isCelebrationXpSource(String? sourceKey) {
  if (sourceKey == null || sourceKey.isEmpty) return false;
  return kCelebrationXpSourceKeys.contains(sourceKey);
}

/// Display label for a skill_breakdown key.
String xpSourceLabel(String breakdownKey) {
  final known = kXpBreakdownLabels[breakdownKey];
  if (known != null) return known;
  return breakdownKey
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

/// Format meters as `N m` / `N.N km` / `N km` (matches profile exploration).
String formatExplorationDistance(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  final km = meters / 1000.0;
  if (km < 10) {
    return '${km.toStringAsFixed(1)} km';
  }
  return '${km.round()} km';
}

/// Walk-distance badge label with the meters that earned the XP.
String exploreDistanceXpLabel(String sourceKey, double meters) {
  final formatted = formatExplorationDistance(meters);
  switch (sourceKey) {
    case 'explore_100m_passively':
      return 'Explore $formatted passively';
    case 'explore_100m_actively':
      return 'Explore $formatted actively';
    default:
      return xpSourceLabel(sourceKey);
  }
}

/// Infer meters from a distance-XP amount using the base XP-per-100 m rate.
double? metersForDistanceXp(
  String sourceKey,
  int xpAmount, {
  double? xpPer100m,
}) {
  if (xpAmount <= 0) return null;
  final rate = xpPer100m ?? _xpPer100mForSource(sourceKey);
  if (rate == null || rate <= 0) return null;
  return (xpAmount / rate) * 100.0;
}

double? _xpPer100mForSource(String sourceKey) {
  switch (sourceKey) {
    case 'explore_100m_passively':
      if (GameConfig.isLoaded) {
        return GameConfig.instance.fieldSurvey.explore100mPassivelyXp;
      }
      return 10.0;
    case 'explore_100m_actively':
      if (GameConfig.isLoaded) {
        return GameConfig.instance.fieldSurvey.explore100mActivelyXp;
      }
      return 20.0;
    default:
      return null;
  }
}

/// Badge/plaque label for an award; distance sources include earned meters.
String xpSourceLabelForAward(String breakdownKey, int amount) {
  if (kDistanceXpSourceKeys.contains(breakdownKey)) {
    final meters = metersForDistanceXp(breakdownKey, amount);
    if (meters != null) {
      return exploreDistanceXpLabel(breakdownKey, meters);
    }
  }
  return xpSourceLabel(breakdownKey);
}

/// Badge label after a closed-app walk gap is credited on reopen.
String exploredSinceLastVisitLabel(double meters) {
  return 'Explored ${formatExplorationDistance(meters)} since last visit';
}

/// Breakdown keys for walk-distance XP (active GPS / passive Health).
const kDistanceXpSourceKeys = <String>{
  'explore_100m_actively',
  'explore_100m_passively',
};

/// Badge sources that accrue in the background as many small batches.
///
/// While the app is backgrounded, **all** floating-badge XP sources are held
/// and flushed as one badge per source (summed amount, refreshed distance
/// labels) when the player returns — see [XpAwardController.setAppForeground].
/// Celebration sources are never bundled; they stay stashed for separate plaques.
const kBackgroundBundleXpSourceKeys = <String>{
  // Kept for docs/tests; runtime bundling is any non-celebration badge source.
  'document_progress',
  'explore_100m_actively',
  'explore_100m_passively',
  'disguise_of_site',
};

/// True for floating-badge sources that should merge across a background session.
///
/// Celebration keys return false (plaques stay separate). Unknown / remainder
/// fallbacks (empty key) are treated as badges and do bundle.
bool isBackgroundBundleXpSource(String? sourceKey) {
  return !isCelebrationXpSource(sourceKey);
}
