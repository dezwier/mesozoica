class DinosaurSummary {
  const DinosaurSummary({
    required this.id,
    required this.name,
    required this.wikipediaTitle,
    this.birth,
    this.death,
    this.period,
    this.dietType,
    this.length,
    this.mass,
    this.location,
    this.shortDescription,
    this.cladogram = const {},
    this.mainImageUrl,
  });

  final int id;
  final String name;
  final String wikipediaTitle;
  final double? birth;
  final double? death;
  final String? period;
  final String? dietType;
  final String? length;
  final String? mass;
  final String? location;
  final String? shortDescription;
  final Map<String, dynamic> cladogram;
  final String? mainImageUrl;

  factory DinosaurSummary.fromJson(Map<String, dynamic> json) {
    return DinosaurSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      wikipediaTitle: json['wikipedia_title'] as String,
      birth: (json['birth'] as num?)?.toDouble(),
      death: (json['death'] as num?)?.toDouble(),
      period: json['period'] as String?,
      dietType: json['diet_type'] as String?,
      length: json['length'] as String?,
      mass: json['mass'] as String?,
      location: json['location'] as String?,
      shortDescription: json['short_description'] as String?,
      cladogram: Map<String, dynamic>.from(json['cladogram'] as Map? ?? {}),
      mainImageUrl: json['main_image_url'] as String?,
    );
  }

  /// Taxonomic lineage from [fromRank] through genus, in original cladogram order.
  List<String> cladogramLineage({String fromRank = 'Dinosauria'}) {
    final entries = <MapEntry<String, String>>[];
    for (final entry in cladogram.entries) {
      final value = entry.value?.toString().trim();
      if (value == null || value.isEmpty) continue;
      entries.add(MapEntry(entry.key, value));
    }

    final startIndex = entries.indexWhere(
      (entry) => entry.value.toLowerCase().contains(fromRank.toLowerCase()),
    );
    if (startIndex < 0) return [];

    final lineage = <String>[];
    for (final entry in entries.sublist(startIndex)) {
      if (entry.key == 'species') break;
      lineage.add(entry.value);
      if (entry.key == 'genus') break;
    }
    return lineage;
  }

  String get displayPeriod {
    if (period != null && period!.isNotEmpty) {
      if (birth != null && death != null) {
        return '$period, ${birth!.round()} – ${death!.round()} Ma';
      }
      return period!;
    }
    if (birth != null && death != null) {
      return '${birth!.round()} – ${death!.round()} Ma';
    }
    return '—';
  }
}

class DinosaurListResponse {
  const DinosaurListResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasNext,
  });

  final List<DinosaurSummary> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasNext;

  bool get hasMore => hasNext;

  factory DinosaurListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .map((item) => DinosaurSummary.fromJson(item as Map<String, dynamic>))
        .toList();
    final total = json['total'] as int? ?? rawItems.length;
    final limit = json['limit'] as int? ?? rawItems.length;
    final offset = json['offset'] as int? ?? 0;
    final hasNext = json['has_next'] as bool? ??
        (offset + items.length < total);
    return DinosaurListResponse(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
      hasNext: hasNext,
    );
  }
}
