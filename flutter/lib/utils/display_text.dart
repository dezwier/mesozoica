/// Uppercases only the first character; leaves the rest unchanged.
String capitalizeLeadingLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// Canonical taxon name for merge keys and compact labels.
String canonicalTaxonName(String value) {
  var text = value.replaceAll(RegExp(r'[\u00A0\u200B\uFEFF]'), ' ');
  text = text.trim();
  if (text.isEmpty) return text;

  text = text.replaceAll(RegExp(r'[†‡×✕✖⨯]'), '');
  text = text.replaceAll(RegExp(r'\s*\(\?\)\s*$'), '');
  text = text.replaceAll(RegExp(r'\s*\(\s*\?\s*\)\s*$'), '');
  text = text.replaceAll(
    RegExp(r'\s*\([^)]*\b\d{3,4}\b[^)]*\)\s*$'),
    '',
  );
  text = text.replaceAll(RegExp(r'\s*\([^)]*\?\s*[^)]*\)\s*$'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

/// Case-insensitive merge key for phylogeny trie nodes.
String taxonMergeKey(String value) => canonicalTaxonName(value).toLowerCase();

/// Short taxon name for compact labels.
String displayTaxonName(String value) => canonicalTaxonName(value);

String displayFactValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '—';
  return capitalizeLeadingLetter(trimmed);
}
