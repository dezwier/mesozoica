/// Answer returned by the field assistant.
class AssistantAnswer {
  const AssistantAnswer({required this.answer, required this.papers});

  final String answer;
  final List<PaperLink> papers;

  factory AssistantAnswer.fromJson(Map<String, dynamic> json) {
    final raw = json['papers'] as List<dynamic>? ?? const [];
    return AssistantAnswer(
      answer: json['answer'] as String? ?? '',
      papers: raw
          .whereType<Map<String, dynamic>>()
          .map(PaperLink.fromJson)
          .where((p) => p.title.isNotEmpty && p.url.isNotEmpty)
          .toList(),
    );
  }
}

class PaperLink {
  const PaperLink({required this.title, required this.url});

  final String title;
  final String url;

  factory PaperLink.fromJson(Map<String, dynamic> json) {
    return PaperLink(
      title: (json['title'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
    );
  }
}
