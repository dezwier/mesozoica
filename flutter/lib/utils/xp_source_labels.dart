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
