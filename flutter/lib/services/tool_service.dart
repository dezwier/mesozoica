import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/tool.dart';

class ToolService {
  ToolService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ToolListResponse> fetchTools({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    bool hasCustomImage = false,
  }) async {
    final uri = AppConfig.toolsUri(
      limit: limit,
      offset: offset,
      sort: sort,
      seed: seed,
      q: q,
      hasCustomImage: hasCustomImage,
    );
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load tools (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tools response');
    }
    return ToolListResponse.fromJson(decoded);
  }

  Future<ToolSummary> fetchToolById(int id) async {
    final uri = AppConfig.toolUri(id);
    if (kDebugMode) {
      debugPrint('ToolService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw ToolServiceException('Tool not found');
    }
    if (response.statusCode != 200) {
      throw ToolServiceException(
        'Failed to load tool (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ToolServiceException('Invalid tool response');
    }
    return ToolSummary.fromJson(decoded);
  }

  void dispose() {
    _client.close();
  }
}

class ToolServiceException implements Exception {
  const ToolServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
