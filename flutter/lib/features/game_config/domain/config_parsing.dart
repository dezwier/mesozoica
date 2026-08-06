// Shared, UI-independent coercion helpers used by document parsers.

Map<String, dynamic> configAsMap(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('Expected YAML mapping, got ${raw.runtimeType}');
}

double configAsDouble(dynamic value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? configAsOptionalDouble(dynamic value, double? fallback) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int configAsInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String configAsString(dynamic value, String fallback) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return fallback;
}

List<String> configAsStringList(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item != null) item.toString(),
  ];
}

Map<int, double> configAsIntDoubleMap(dynamic raw) {
  if (raw is! Map) return {};
  final out = <int, double>{};
  for (final entry in raw.entries) {
    final key = int.tryParse(entry.key.toString());
    if (key != null && entry.value is num) {
      out[key] = (entry.value as num).toDouble();
    }
  }
  return out;
}

Map<String, double> configAsStringDoubleMap(dynamic raw) {
  if (raw is! Map) return {};
  final out = <String, double>{};
  for (final entry in raw.entries) {
    if (entry.value is num) {
      out[entry.key.toString()] = (entry.value as num).toDouble();
    }
  }
  return out;
}
