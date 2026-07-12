import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/fossil.dart';

class FossilService {
  FossilService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<FossilListResponse> fetchFossils({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
  }) async {
    final uri = AppConfig.fossilsUri(
      limit: limit,
      offset: offset,
      sort: sort,
      seed: seed,
      q: q,
      maYounger: maYounger,
      maOlder: maOlder,
      hasCustomImage: hasCustomImage,
    );
    if (kDebugMode) {
      debugPrint('FossilService GET $uri');
    }
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw FossilServiceException(
        'Failed to load fossils (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FossilServiceException('Invalid fossils response');
    }
    return FossilListResponse.fromJson(decoded);
  }

  void dispose() {
    _client.close();
  }
}

class FossilServiceException implements Exception {
  const FossilServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
