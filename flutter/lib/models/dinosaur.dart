import '../utils/display_text.dart';
import '../utils/relative_time.dart';
import 'owned_occurrence_thumb.dart';

export 'owned_occurrence_thumb.dart';

class CladogramNode {
  const CladogramNode({
    required this.rankKey,
    required this.rankLabel,
    required this.name,
  });

  final String rankKey;
  final String rankLabel;
  final String name;
}

class DinosaurSummary {
  const DinosaurSummary({
    required this.id,
    required this.name,
    required this.wikipediaTitle,
    this.dinosaurTypeId,
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
    this.insertDate,
    this.articleDate,
    this.createdAt,
    this.version,
    this.status,
    this.ownedOccurrences = const [],
  });

  final int id;
  final String name;
  final String wikipediaTitle;
  final int? dinosaurTypeId;
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

  /// When the catalog dinosaur_type row was first inserted.
  final DateTime? insertDate;

  /// Wikipedia article timestamp for this card's content revision.
  final DateTime? articleDate;

  /// Inventory reconstruction time; null for catalog rows.
  final DateTime? createdAt;

  /// Curated image version folder; set for inventory occurrences.
  final String? version;

  /// Viewer collection status (hidden / modelled / reconstructed).
  final String? status;

  /// Catalog mode: owned occurrence thumbs for the album gallery.
  final List<OwnedOccurrenceThumb> ownedOccurrences;

  /// True when the viewer owns at least one occurrence of this catalog type.
  bool get isCatalogOwned => ownedOccurrences.isNotEmpty;

  /// True for owned/reconstructed dinosaur cards (not catalog types).
  bool get isInventoryOccurrence =>
      createdAt != null || (dinosaurTypeId != null && dinosaurTypeId != id);

  bool get isHidden => (status ?? 'hidden').trim().toLowerCase() == 'hidden';

  String get displayOccurrenceNumber => '#$id';

  /// Front top-left badge: `#99 · Original`.
  String get occurrenceIdBadgeLabel {
    final versionPart = version?.trim() ?? '';
    if (versionPart.isEmpty) return displayOccurrenceNumber;
    return '$displayOccurrenceNumber · $versionPart';
  }

  /// Card-back subtitle for inventory occurrences.
  /// Id and version are shown separately as [OccurrenceIdBadge] on the front.
  String? get reconstructedSubtitle {
    final at = createdAt;
    if (at == null) return null;
    return 'Reconstructed ${formatRelativeWhen(at)}';
  }

  /// Build an inventory-style summary for a catalog owned occurrence thumb.
  DinosaurSummary occurrenceFromThumb(OwnedOccurrenceThumb thumb) {
    return DinosaurSummary(
      id: thumb.id,
      name: name,
      wikipediaTitle: wikipediaTitle,
      dinosaurTypeId: dinosaurTypeId ?? id,
      birth: birth,
      death: death,
      period: period,
      dietType: dietType,
      length: length,
      mass: mass,
      location: location,
      shortDescription: shortDescription,
      cladogram: cladogram,
      mainImageUrl: thumb.mainImageUrl ?? mainImageUrl,
      insertDate: insertDate,
      articleDate: articleDate,
      createdAt: thumb.createdAt,
      version: thumb.version,
      status: status,
    );
  }

  /// Catalog album: append a newly collected occurrence thumb.
  DinosaurSummary withAddedOwnedOccurrence(DinosaurSummary created) {
    return DinosaurSummary(
      id: id,
      name: name,
      wikipediaTitle: wikipediaTitle,
      dinosaurTypeId: dinosaurTypeId,
      birth: birth,
      death: death,
      period: period,
      dietType: dietType,
      length: length,
      mass: mass,
      location: location,
      shortDescription: shortDescription,
      cladogram: cladogram,
      mainImageUrl: mainImageUrl,
      insertDate: insertDate,
      articleDate: articleDate,
      createdAt: createdAt,
      version: version,
      status: created.status ?? status,
      ownedOccurrences: [
        ...ownedOccurrences,
        OwnedOccurrenceThumb(
          id: created.id,
          version: created.version,
          mainImageUrl: created.mainImageUrl,
          createdAt: created.createdAt,
        ),
      ],
    );
  }

  factory DinosaurSummary.fromJson(Map<String, dynamic> json) {
    final rawOwned = json['owned_occurrences'];
    final owned = rawOwned is List
        ? rawOwned
              .whereType<Map<String, dynamic>>()
              .map(OwnedOccurrenceThumb.fromJson)
              .toList()
        : const <OwnedOccurrenceThumb>[];
    return DinosaurSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      wikipediaTitle: json['wikipedia_title'] as String,
      dinosaurTypeId: json['dinosaur_type_id'] as int?,
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
      insertDate: _parseDate(json['insert_date']),
      articleDate: _parseDate(json['article_date']),
      createdAt: _parseDate(json['created_at']),
      version: (json['version'] as String?)?.trim().isNotEmpty == true
          ? (json['version'] as String).trim()
          : null,
      status: json['status'] as String?,
      ownedOccurrences: owned,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static String cladogramRankLabel(String rankKey) {
    return rankKey.replaceAll(RegExp(r'_\d+$'), '').toUpperCase();
  }

  /// Taxonomic lineage from [fromRank] through genus, in original cladogram order.
  List<CladogramNode> cladogramNodes({String fromRank = 'Dinosauria'}) {
    final entries = <MapEntry<String, String>>[];
    for (final entry in cladogram.entries) {
      final value = canonicalTaxonName(entry.value?.toString() ?? '');
      if (value.isEmpty) continue;
      entries.add(MapEntry(entry.key, value));
    }

    final startIndex = entries.indexWhere(
      (entry) => entry.value.toLowerCase().contains(fromRank.toLowerCase()),
    );
    if (startIndex < 0) return [];

    final nodes = <CladogramNode>[];
    for (final entry in entries.sublist(startIndex)) {
      if (entry.key == 'species') break;
      nodes.add(
        CladogramNode(
          rankKey: entry.key,
          rankLabel: cladogramRankLabel(entry.key),
          name: entry.value,
        ),
      );
      if (entry.key == 'genus') break;
    }
    return nodes;
  }

  List<String> cladogramLineage({String fromRank = 'Dinosauria'}) {
    return cladogramNodes(fromRank: fromRank).map((node) => node.name).toList();
  }

  String get displayPeriod {
    if (birth != null && death != null) {
      final maLabel = birth!.round() == death!.round()
          ? '${birth!.round()} Ma'
          : '${birth!.round()} – ${death!.round()} Ma';
      if (period != null && period!.isNotEmpty) {
        return '$period, $maLabel';
      }
      return maLabel;
    }
    if (period != null && period!.isNotEmpty) {
      return period!;
    }
    return '—';
  }

  /// Period name only — omits Ma range (for card front).
  String get displayPeriodName {
    final name = period?.trim();
    if (name == null || name.isEmpty) return '—';
    final commaIndex = name.indexOf(',');
    if (commaIndex > 0) {
      final suffix = name.substring(commaIndex + 1).trim();
      if (RegExp(r'\d').hasMatch(suffix) && suffix.contains('Ma')) {
        return name.substring(0, commaIndex).trim();
      }
    }
    return name;
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
    final hasNext =
        json['has_next'] as bool? ?? (offset + items.length < total);
    return DinosaurListResponse(
      items: items,
      total: total,
      limit: limit,
      offset: offset,
      hasNext: hasNext,
    );
  }
}
