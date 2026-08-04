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

/// Human labels for skill_breakdown keys (XP sources / main_param awards).
const kXpBreakdownLabels = <String, String>{
  'sites': 'Sites discovered',
  'fossils': 'Fossils discovered',
  'active_distance': 'Active distance',
  'passive_distance': 'Passive distance',
  'disguise': 'Site disguise',
  'site_exploration': 'Site exploration',
  'site_documentation': 'Site documentation',
  'site_identification': 'Site identification',
  'first_discovery': 'First discovery',
  'first_documentation': 'First documentation',
};

/// Breakdown keys for **big-event celebrations** (embedded in the plaque).
///
/// Not shown as floating XP badges. See library doc on this file.
const kCelebrationXpSourceKeys = <String>{
  'sites',
  'first_discovery',
  'fossils',
  'site_documentation',
  'first_documentation',
  'site_identification',
};

/// Keys claimed by the site-discovered celebration.
const kSiteDiscoveryCelebrationXpKeys = <String>{
  'sites',
  'first_discovery',
};

/// Keys claimed by fossil discovery celebrations.
const kFossilDiscoveryCelebrationXpKeys = <String>{
  'fossils',
};

/// Keys claimed by the site-documented celebration.
const kSiteDocumentationCelebrationXpKeys = <String>{
  'site_documentation',
  'first_documentation',
};

/// Keys claimed by the site-identified celebration.
const kSiteIdentificationCelebrationXpKeys = <String>{
  'site_identification',
};

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
