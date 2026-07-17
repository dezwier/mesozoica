class ToolSummary {
  const ToolSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.scientificTool,
    required this.description,
    required this.rarity,
    this.mainImageUrl,
  });

  final int id;
  final String name;
  final String category;
  final String scientificTool;
  final String description;
  final int rarity;
  final String? mainImageUrl;

  String get displayCategory =>
      category.replaceAll('_', ' ').split(' ').map(_titleCaseWord).join(' ');

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
      mainImageUrl: json['main_image_url'] as String?,
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
