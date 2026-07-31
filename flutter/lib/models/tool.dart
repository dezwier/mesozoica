import '../utils/relative_time.dart';
import 'owned_occurrence_thumb.dart';

export 'owned_occurrence_thumb.dart';

class ToolSummary {
  const ToolSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.scientificTool,
    required this.description,
    required this.rarity,
    this.action = 'Use',
    this.mainImageUrl,
    this.level,
    this.toolTypeId,
    this.params = const {},
    this.baseParams = const {},
    this.spawnDate,
    this.version,
    this.ownedOccurrences = const [],
  });

  final int id;
  final String name;
  final String category;
  final String scientificTool;
  final String description;
  final int rarity;

  /// Verb shown on the card Actions panel (e.g. Deploy, Read).
  final String action;
  final String? mainImageUrl;

  /// Collection level when owned; null when not in the user's collection.
  final int? level;
  final int? toolTypeId;
  final Map<String, dynamic> params;
  final Map<String, dynamic> baseParams;

  /// Inventory obtain time; null for catalog rows.
  final DateTime? spawnDate;

  /// Curated image version folder; set for inventory occurrences.
  final String? version;

  /// Catalog mode: owned occurrence thumbs for the album gallery.
  final List<OwnedOccurrenceThumb> ownedOccurrences;

  bool get isOwned => level != null || ownedOccurrences.isNotEmpty;

  /// True when the viewer owns at least one occurrence of this catalog type.
  bool get isCatalogOwned => ownedOccurrences.isNotEmpty;
  /// True when this card represents a specific owned tool occurrence (inventory).
  ///
  /// Prefer [spawnDate] over `id != toolTypeId`: the first occurrence of the
  /// first tool type can share id `1` with its type, which would otherwise
  /// look like a catalog row (e.g. Aerial Scout `#1`).
  bool get isToolInstance =>
      spawnDate != null || (toolTypeId != null && toolTypeId != id);

  String get displayOccurrenceNumber => '#$id';

  /// Front top-left badge: `#10 · Original`.
  String get occurrenceIdBadgeLabel {
    final versionPart = version?.trim() ?? '';
    if (versionPart.isEmpty) return displayOccurrenceNumber;
    return '$displayOccurrenceNumber · $versionPart';
  }

  /// Card-back subtitle: category / scientific, plus Obtained when known.
  /// Id and version are shown separately as [OccurrenceIdBadge] on the front.
  String inventoryBackSubtitle() {
    final base = categoryWithScientificDisplay();
    final at = spawnDate;
    if (at == null) return base;
    final obtained = 'Obtained ${formatRelativeWhen(at)}';
    if (base.isEmpty) return obtained;
    return '$base - $obtained';
  }

  /// Build an inventory-style summary for a catalog owned occurrence thumb.
  ToolSummary occurrenceFromThumb(OwnedOccurrenceThumb thumb) {
    return ToolSummary(
      id: thumb.id,
      name: name,
      category: category,
      scientificTool: scientificTool,
      description: description,
      rarity: rarity,
      action: action,
      mainImageUrl: thumb.mainImageUrl ?? mainImageUrl,
      level: level ?? 1,
      toolTypeId: toolTypeId ?? id,
      params: params,
      baseParams: baseParams,
      spawnDate: thumb.spawnDate,
      version: thumb.version,
    );
  }

  /// Catalog album: append a newly collected occurrence thumb.
  ToolSummary withAddedOwnedOccurrence(ToolSummary created) {
    return copyWith(
      level: created.level ?? level ?? 1,
      ownedOccurrences: [
        ...ownedOccurrences,
        OwnedOccurrenceThumb(
          id: created.id,
          version: created.version,
          mainImageUrl: created.mainImageUrl,
          spawnDate: created.spawnDate,
        ),
      ],
    );
  }

  ToolSummary copyWith({
    int? id,
    String? name,
    String? category,
    String? scientificTool,
    String? description,
    int? rarity,
    String? action,
    String? mainImageUrl,
    int? level,
    int? toolTypeId,
    Map<String, dynamic>? params,
    Map<String, dynamic>? baseParams,
    DateTime? spawnDate,
    String? version,
    List<OwnedOccurrenceThumb>? ownedOccurrences,
    bool clearLevel = false,
  }) {
    return ToolSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      scientificTool: scientificTool ?? this.scientificTool,
      description: description ?? this.description,
      rarity: rarity ?? this.rarity,
      action: action ?? this.action,
      mainImageUrl: mainImageUrl ?? this.mainImageUrl,
      level: clearLevel ? null : (level ?? this.level),
      toolTypeId: toolTypeId ?? this.toolTypeId,
      params: params ?? this.params,
      baseParams: baseParams ?? this.baseParams,
      spawnDate: spawnDate ?? this.spawnDate,
      version: version ?? this.version,
      ownedOccurrences: ownedOccurrences ?? this.ownedOccurrences,
    );
  }

  String get displayCategory {
    final stripped = category.replaceFirst(RegExp(r'^\d+\s+'), '');
    return stripped
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(_titleCaseWord)
        .join(' ');
  }

  String get displayScientificTool => scientificTool
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map(_titleCaseWord)
      .join(' ');

  String get categoryWithScientific => categoryWithScientificDisplay();

  String categoryWithScientificDisplay() {
    final parts = <String>[
      if (displayCategory.isNotEmpty) displayCategory,
      if (displayScientificTool.isNotEmpty) displayScientificTool,
    ];
    return parts.join(' - ');
  }

  static String _titleCaseWord(String word) {
    if (word.isEmpty) return word;
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }

  factory ToolSummary.fromJson(Map<String, dynamic> json) {
    final rawOwned = json['owned_occurrences'];
    final owned = rawOwned is List
        ? rawOwned
            .whereType<Map<String, dynamic>>()
            .map(OwnedOccurrenceThumb.fromJson)
            .toList()
        : const <OwnedOccurrenceThumb>[];
    return ToolSummary(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      scientificTool: json['scientific_tool'] as String? ?? '',
      description: json['description'] as String? ?? '',
      rarity: json['rarity'] as int? ?? 1,
      action: json['action'] as String? ?? 'Use',
      mainImageUrl: json['main_image_url'] as String?,
      level: json['level'] as int?,
      toolTypeId: json['tool_type_id'] as int?,
      params: (json['params'] as Map<String, dynamic>?) ?? const {},
      baseParams: (json['base_params'] as Map<String, dynamic>?) ?? const {},
      spawnDate: _parseDate(json['spawn_date']),
      version: (json['version'] as String?)?.trim().isNotEmpty == true
          ? (json['version'] as String).trim()
          : null,
      ownedOccurrences: owned,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

class ToolListResponse {
  const ToolListResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  final List<ToolSummary> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  factory ToolListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ToolListResponse(
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(ToolSummary.fromJson)
                .toList()
          : const [],
      total: json['total'] as int? ?? 0,
      limit: json['limit'] as int? ?? 0,
      offset: json['offset'] as int? ?? 0,
      hasMore: json['has_next'] as bool? ?? false,
    );
  }
}

class ToolCategoryOption {
  const ToolCategoryOption({required this.value, required this.label});

  final String value;
  final String label;

  factory ToolCategoryOption.fromJson(Map<String, dynamic> json) {
    return ToolCategoryOption(
      value: json['value'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }
}
