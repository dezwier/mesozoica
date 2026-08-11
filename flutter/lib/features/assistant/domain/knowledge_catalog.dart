/// Indexed dinosaur available to the field assistant.
class KnowledgeSubject {
  const KnowledgeSubject({required this.id, required this.name});

  final String id;
  final String name;

  factory KnowledgeSubject.fromJson(Map<String, dynamic> json) {
    return KnowledgeSubject(
      id: (json['id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
    );
  }
}

/// One browseable knowledge document (wiki page or paper).
class KnowledgeSourceItem {
  const KnowledgeSourceItem({
    required this.title,
    required this.url,
    required this.kind,
  });

  final String title;
  final String url;
  final String kind;

  bool get isWikipedia => kind == 'wikipedia';

  factory KnowledgeSourceItem.fromJson(Map<String, dynamic> json) {
    return KnowledgeSourceItem(
      title: (json['title'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
      kind: (json['kind'] as String? ?? '').trim(),
    );
  }
}

class KnowledgeSourceGroup {
  const KnowledgeSourceGroup({required this.kind, required this.items});

  final String kind;
  final List<KnowledgeSourceItem> items;

  factory KnowledgeSourceGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? const [];
    return KnowledgeSourceGroup(
      kind: (json['kind'] as String? ?? '').trim(),
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(KnowledgeSourceItem.fromJson)
          .where((item) => item.title.isNotEmpty && item.url.isNotEmpty)
          .toList(),
    );
  }

  String get label {
    switch (kind) {
      case 'wikipedia':
        return 'Wikipedia';
      case 'openalex':
        return 'OpenAlex';
      default:
        return kind.isEmpty ? 'Sources' : kind;
    }
  }
}

class KnowledgeSources {
  const KnowledgeSources({
    required this.subjectId,
    required this.subjectName,
    required this.groups,
  });

  final String subjectId;
  final String subjectName;
  final List<KnowledgeSourceGroup> groups;

  factory KnowledgeSources.fromJson(Map<String, dynamic> json) {
    final raw = json['groups'] as List<dynamic>? ?? const [];
    return KnowledgeSources(
      subjectId: (json['subject_id'] as String? ?? '').trim(),
      subjectName: (json['subject_name'] as String? ?? '').trim(),
      groups: raw
          .whereType<Map<String, dynamic>>()
          .map(KnowledgeSourceGroup.fromJson)
          .where((group) => group.items.isNotEmpty)
          .toList(),
    );
  }
}
