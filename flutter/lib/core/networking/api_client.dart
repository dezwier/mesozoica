import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'api_transport.dart';
import 'token_storage.dart';

typedef TokenRefreshCallback = Future<bool> Function();

class ApiClient implements ApiTransport {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Optional hook (wired by [AuthController]) to mint a fresh JWT via Firebase.
  TokenRefreshCallback? onUnauthorized;

  Future<bool>? _refreshInFlight;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool skipAuth = false,
  }) async {
    final uri = _uri(path, query);
    final response = await _sendWithAuthRetry(
      skipAuth: skipAuth,
      send: (headers) => http.get(uri, headers: headers),
    );
    return _decode(response);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool skipAuth = false,
  }) async {
    final uri = _uri(path);
    final response = await _sendWithAuthRetry(
      skipAuth: skipAuth,
      send: (headers) => http.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  @override
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path);
    final response = await _sendWithAuthRetry(
      skipAuth: false,
      send: (headers) => http.patch(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  @override
  Future<Map<String, dynamic>> delete(String path) async {
    final uri = _uri(path);
    final response = await _sendWithAuthRetry(
      skipAuth: false,
      send: (headers) => http.delete(uri, headers: headers),
    );
    return _decode(response);
  }

  @override
  Future<http.StreamedResponse> multipart(
    String path,
    List<int> bytes,
    String filename,
  ) async {
    Future<http.StreamedResponse> send(Map<String, String> headers) async {
      final uri = _uri(path);
      final request = http.MultipartRequest('POST', uri);
      final requestHeaders = Map<String, String>.from(headers)
        ..remove('Content-Type');
      request.headers.addAll(requestHeaders);
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
      return request.send();
    }

    final headers = await _headers(false);
    var streamed = await send(headers);
    if (streamed.statusCode == 401 && await _tryRefreshToken()) {
      streamed = await send(await _headers(false));
    }
    return streamed;
  }

  /// Sends a GET request to an already-built [uri] (e.g. from one of
  /// [AppConfig]'s Uri builders), returning the raw response so callers can
  /// keep their own status-code/error handling. Passing [client] routes the
  /// request through it instead of the top-level `http` functions, which is
  /// how domain services keep supporting `MockClient` injection in tests.
  @override
  Future<http.Response> sendGet(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Duration? timeout,
    bool skipAuth = false,
  }) {
    return _sendRawWithAuthRetry(
      skipAuth: skipAuth,
      headers: headers,
      timeout: timeout,
      send: (merged) {
        final future = client != null
            ? client.get(uri, headers: merged)
            : http.get(uri, headers: merged);
        return timeout == null ? future : future.timeout(timeout);
      },
    );
  }

  /// POST equivalent of [sendGet] for an already-built [uri].
  @override
  Future<http.Response> sendPost(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    bool skipAuth = false,
  }) {
    return _sendRawWithAuthRetry(
      skipAuth: skipAuth,
      headers: headers,
      timeout: timeout,
      send: (merged) {
        final future = client != null
            ? client.post(uri, headers: merged, body: body)
            : http.post(uri, headers: merged, body: body);
        return timeout == null ? future : future.timeout(timeout);
      },
    );
  }

  /// DELETE equivalent of [sendGet] for an already-built [uri].
  @override
  Future<http.Response> sendDelete(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Duration? timeout,
    bool skipAuth = false,
  }) {
    return _sendRawWithAuthRetry(
      skipAuth: skipAuth,
      headers: headers,
      timeout: timeout,
      send: (merged) {
        final future = client != null
            ? client.delete(uri, headers: merged)
            : http.delete(uri, headers: merged);
        return timeout == null ? future : future.timeout(timeout);
      },
    );
  }

  /// PATCH equivalent of [sendGet] for an already-built [uri].
  @override
  Future<http.Response> sendPatch(
    Uri uri, {
    http.Client? client,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    bool skipAuth = false,
  }) {
    return _sendRawWithAuthRetry(
      skipAuth: skipAuth,
      headers: headers,
      timeout: timeout,
      send: (merged) {
        final future = client != null
            ? client.patch(uri, headers: merged, body: body)
            : http.patch(uri, headers: merged, body: body);
        return timeout == null ? future : future.timeout(timeout);
      },
    );
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = AppConfig.baseApiUrl;
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalized').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers(bool skipAuth) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (!skipAuth) {
      final token = await TokenStorage.loadToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<Map<String, String>> _mergeAuthHeader(
    Map<String, String>? headers,
  ) async {
    final merged = <String, String>{...?headers};
    final token = TokenStorage.cachedToken;
    if (token != null && token.isNotEmpty) {
      merged['Authorization'] = 'Bearer $token';
    } else if (!merged.containsKey('Authorization')) {
      merged.remove('Authorization');
    }
    return merged;
  }

  Future<bool> _tryRefreshToken() async {
    final callback = onUnauthorized;
    if (callback == null) return false;
    if (_refreshInFlight != null) return _refreshInFlight!;
    _refreshInFlight = callback().whenComplete(() {
      _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  Future<http.Response> _sendWithAuthRetry({
    required bool skipAuth,
    required Future<http.Response> Function(Map<String, String> headers) send,
  }) async {
    var response = await send(await _headers(skipAuth));
    if (response.statusCode == 401 && !skipAuth && await _tryRefreshToken()) {
      response = await send(await _headers(false));
    }
    return response;
  }

  Future<http.Response> _sendRawWithAuthRetry({
    required bool skipAuth,
    required Map<String, String>? headers,
    required Duration? timeout,
    required Future<http.Response> Function(Map<String, String>? headers) send,
  }) async {
    // Raw repository calls commonly supply only content headers. Authentication
    // belongs to the transport, so merge the stored token on the first request
    // as well as after a refresh. Missing auth is a 403 in the backend and
    // therefore cannot rely on the 401 refresh path to repair the request.
    var response = await send(
      skipAuth ? headers : await _mergeAuthHeader(headers),
    );
    if (response.statusCode == 401 && !skipAuth && await _tryRefreshToken()) {
      response = await send(await _mergeAuthHeader(headers));
    }
    return response;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    }
    if (response.statusCode >= 400) {
      final detail = body?['detail'];
      final message = detail is Map
          ? (detail['message'] as String? ?? detail.toString())
          : detail?.toString() ?? 'Request failed (${response.statusCode})';
      throw ApiException(response.statusCode, message, body: body);
    }
    return body ?? <String, dynamic>{};
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});

  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => message;
}
