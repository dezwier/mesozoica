class OwnedOccurrenceThumb {
  const OwnedOccurrenceThumb({
    required this.id,
    this.version,
    this.mainImageUrl,
    this.createdAt,
    this.spawnDate,
  });

  final int id;
  final String? version;
  final String? mainImageUrl;
  final DateTime? createdAt;
  final DateTime? spawnDate;

  factory OwnedOccurrenceThumb.fromJson(Map<String, dynamic> json) {
    return OwnedOccurrenceThumb(
      id: json['id'] as int,
      version: (json['version'] as String?)?.trim().isNotEmpty == true
          ? (json['version'] as String).trim()
          : null,
      mainImageUrl: json['main_image_url'] as String?,
      createdAt: _parseDate(json['created_at']),
      spawnDate: _parseDate(json['spawn_date']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
