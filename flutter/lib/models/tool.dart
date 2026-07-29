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

  bool get isOwned => level != null;
  /// True when this card represents a specific owned tool occurrence (inventory),
  /// i.e. the instance `id` differs from the catalog `tool_type_id`.
  bool get isToolInstance => toolTypeId != null && toolTypeId != id;

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

  String get categoryWithScientific {
    final idPrefix = isToolInstance ? 'ID $id' : '';
    final parts = <String>[
      if (idPrefix.isNotEmpty) idPrefix,
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
    );
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
