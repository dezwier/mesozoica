import 'package:mesozoica/core/networking/api_client.dart';
import 'package:mesozoica/core/networking/api_transport.dart';
import 'package:mesozoica/features/assistant/domain/assistant_answer.dart';

/// HTTP client for field-assistant Q&A.
class AssistantRepository {
  AssistantRepository({ApiTransport? transport})
    : _transport = transport ?? ApiClient.instance;

  final ApiTransport _transport;

  Future<AssistantAnswer> ask(String question) async {
    final data = await _transport.post(
      '/api/v1/assistant/ask',
      body: {'question': question},
    );
    return AssistantAnswer.fromJson(data);
  }
}
