/// Uppercases only the first character; leaves the rest unchanged.
String capitalizeLeadingLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

String displayFactValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '—';
  return capitalizeLeadingLetter(trimmed);
}
