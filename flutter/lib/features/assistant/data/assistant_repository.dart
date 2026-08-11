import 'package:mesozoica/core/networking/api_client.dart';
import 'package:mesozoica/core/networking/api_transport.dart';
import 'package:mesozoica/features/assistant/domain/assistant_answer.dart';
import 'package:mesozoica/features/assistant/domain/knowledge_catalog.dart';

/// HTTP client for field-assistant Q&A and knowledge browsing.
class AssistantRepository {
  AssistantRepository({ApiTransport? transport})
    : _transport = transport ?? ApiClient.instance;

  final ApiTransport _transport;

  Future<AssistantAnswer> ask(
    String question, {
    String? subjectId,
    String? subjectName,
  }) async {
    final body = <String, dynamic>{'question': question};
    final scoped = subjectId?.trim();
    if (scoped != null && scoped.isNotEmpty) {
      body['subject_id'] = scoped;
    }
    final name = subjectName?.trim();
    if (name != null && name.isNotEmpty) {
      body['subject_name'] = name;
    }
    final data = await _transport.post('/api/v1/assistant/ask', body: body);
    return AssistantAnswer.fromJson(data);
  }

  Future<List<KnowledgeSubject>> listSubjects() async {
    final data = await _transport.get('/api/v1/assistant/subjects');
    final raw = data['subjects'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(KnowledgeSubject.fromJson)
        .where((s) => s.id.isNotEmpty && s.name.isNotEmpty)
        .toList();
  }

  Future<KnowledgeSources> listSources(String subjectId) async {
    final data = await _transport.get(
      '/api/v1/assistant/subjects/${Uri.encodeComponent(subjectId)}/sources',
    );
    return KnowledgeSources.fromJson(data);
  }
}
