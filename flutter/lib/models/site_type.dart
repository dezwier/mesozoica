import '../utils/display_text.dart';
import 'owned_occurrence_thumb.dart';

export 'owned_occurrence_thumb.dart';

class SiteTypeSummary {
  const SiteTypeSummary({
    required this.id,
    required this.period,
    required this.rockType,
    this.mainImageUrl,
    this.ownedOccurrences = const [],
  });

  final int id;
  final String period;
  final String rockType;
  final String? mainImageUrl;

  /// Catalog mode: owned site occurrence thumbs for the album gallery.
  final List<OwnedOccurrenceThumb> ownedOccurrences;

  /// True when the viewer owns at least one site of this type.
  bool get isCatalogOwned => ownedOccurrences.isNotEmpty;

  /// Title-cased period + rock type (e.g. `Cretaceous Sandstone`).
  String get displayTitle {
    final parts = <String>[];
    final periodPart = period.trim();
    final rockPart = rockType.trim();
    if (periodPart.isNotEmpty) {
      parts.add(toTitleCase(periodPart));
    }
    if (rockPart.isNotEmpty) {
      parts.add(toTitleCase(rockPart));
    }
    return parts.isNotEmpty ? parts.join(' ') : 'Site type';
  }

  factory SiteTypeSummary.fromJson(Map<String, dynamic> json) {
    final rawOwned = json['owned_occurrences'];
    return SiteTypeSummary(
      id: json['id'] as int,
      period: json['period'] as String? ?? '',
      rockType: json['rock_type'] as String? ?? '',
      mainImageUrl: json['main_image_url'] as String?,
      ownedOccurrences: rawOwned is List
          ? rawOwned
                .whereType<Map<String, dynamic>>()
                .map(OwnedOccurrenceThumb.fromJson)
                .toList()
          : const [],
    );
  }
}

class SiteTypeListResponse {
  const SiteTypeListResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasNext,
  });

  final List<SiteTypeSummary> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasNext;

  bool get hasMore => hasNext;

  factory SiteTypeListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SiteTypeListResponse(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(SiteTypeSummary.fromJson)
                .toList()
          : const [],
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? 0,
      offset: json['offset'] as int? ?? 0,
      hasNext: json['has_next'] as bool? ?? false,
    );
  }
}
