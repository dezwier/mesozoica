class DinosaurArticle {
  const DinosaurArticle({
    required this.id,
    required this.name,
    required this.wikipediaTitle,
    this.article,
    this.articleDate,
  });

  final int id;
  final String name;
  final String wikipediaTitle;
  final String? article;
  final DateTime? articleDate;

  factory DinosaurArticle.fromJson(Map<String, dynamic> json) {
    final rawDate = json['article_date'] as String?;
    return DinosaurArticle(
      id: json['id'] as int,
      name: json['name'] as String,
      wikipediaTitle: json['wikipedia_title'] as String,
      article: json['article'] as String?,
      articleDate: rawDate == null ? null : DateTime.tryParse(rawDate),
    );
  }
}
