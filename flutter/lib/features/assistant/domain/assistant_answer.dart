/// Answer returned by the field assistant.
class AssistantAnswer {
  const AssistantAnswer({required this.answer, required this.sources});

  final String answer;
  final List<SourceLink> sources;

  factory AssistantAnswer.fromJson(Map<String, dynamic> json) {
    final raw = json['sources'] as List<dynamic>? ?? const [];
    return AssistantAnswer(
      answer: json['answer'] as String? ?? '',
      sources: raw
          .whereType<Map<String, dynamic>>()
          .map(SourceLink.fromJson)
          .where((s) => s.text.isNotEmpty || (s.title.isNotEmpty && s.url.isNotEmpty))
          .toList(),
    );
  }
}

class SourceLink {
  const SourceLink({
    required this.title,
    required this.url,
    required this.kind,
    this.text = '',
  });

  final String title;
  final String url;

  /// `wikipedia`, `openalex`, or other source kind from the API.
  final String kind;

  /// Cited evidence chunk text (may be empty for legacy responses).
  final String text;

  bool get isWikipedia => kind == 'wikipedia';

  factory SourceLink.fromJson(Map<String, dynamic> json) {
    return SourceLink(
      title: (json['title'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
      kind: (json['kind'] as String? ?? '').trim(),
      text: (json['text'] as String? ?? '').trim(),
    );
  }
}
