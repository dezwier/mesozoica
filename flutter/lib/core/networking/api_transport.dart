import 'package:http/http.dart' as http;

/// Injectable JSON transport used by feature data repositories.
abstract interface class ApiTransport {
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool skipAuth,
  });

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool skipAuth,
  });

  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body});

  Future<Map<String, dynamic>> delete(String path);

  Future<http.StreamedResponse> multipart(
    String path,
    List<int> bytes,
    String filename,
  );

  Future<http.Response> sendGet(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Duration? timeout,
    bool skipAuth,
  });
  Future<http.Response> sendPost(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    bool skipAuth,
  });
  Future<http.Response> sendDelete(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Duration? timeout,
    bool skipAuth,
  });
  Future<http.Response> sendPatch(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    bool skipAuth,
  });
}
