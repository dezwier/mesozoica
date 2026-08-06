/// Uppercases only the first character; leaves the rest unchanged.
String capitalizeLeadingLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// Title-cases a label, treating `_` and whitespace as word breaks.
///
/// Example: `vulcanic_ash` → `Vulcanic Ash`.
String toTitleCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

/// Canonical taxon name for merge keys and compact labels.
String canonicalTaxonName(String value) {
  var text = value.replaceAll(RegExp(r'[\u00A0\u200B\uFEFF]'), ' ');
  text = text.trim();
  if (text.isEmpty) return text;

  text = text.replaceAll(RegExp(r'[†‡×✕✖⨯]'), '');
  text = text.replaceAll(RegExp(r'\s*\(\?\)\s*$'), '');
  text = text.replaceAll(RegExp(r'\s*\(\s*\?\s*\)\s*$'), '');
  text = text.replaceAll(RegExp(r'\s*\([^)]*\b\d{3,4}\b[^)]*\)\s*$'), '');
  text = text.replaceAll(RegExp(r'\s*\([^)]*\?\s*[^)]*\)\s*$'), '');
  text = _stripTaxonomicAuthority(text);
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

String _stripTaxonomicAuthority(String text) {
  final trailingAuthority = RegExp(
    r'\s+(?:'
    r'(?:[A-Z][A-Za-z.-]*(?:\s+[A-Z]\.?)*(?:\s+(?:&|and)\s+[A-Z][A-Za-z.-]*)*\s+)?'
    r'(?:et\s+al\.?|et\s+all\.?)'
    r'(?:\s*,\s*)?'
    r'(?:\d{3,4})?'
    r'|'
    r'(?:[A-Z][A-Za-z.-]*(?:\s+[A-Z]\.?)*(?:\s+(?:&|and)\s+[A-Z][A-Za-z.-]*)*)'
    r'(?:\s*,\s*|\s+)\d{3,4}'
    r')\s*$',
    caseSensitive: true,
  );

  while (true) {
    final stripped = text.replaceAll(trailingAuthority, '').trim();
    if (stripped == text) break;
    text = stripped;
  }
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
