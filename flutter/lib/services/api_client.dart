import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'token_storage.dart';

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool skipAuth = false,
  }) async {
    final uri = _uri(path, query);
    final response = await http.get(uri, headers: await _headers(skipAuth));
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool skipAuth = false,
  }) async {
    final uri = _uri(path);
    final response = await http.post(
      uri,
      headers: await _headers(skipAuth),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path);
    final response = await http.patch(
      uri,
      headers: await _headers(false),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final uri = _uri(path);
    final response = await http.delete(uri, headers: await _headers(false));
    return _decode(response);
  }

  Future<http.StreamedResponse> multipart(
    String path,
    List<int> bytes,
    String filename,
  ) async {
    final uri = _uri(path);
    final request = http.MultipartRequest('POST', uri);
    final headers = await _headers(false);
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    return request.send();
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
