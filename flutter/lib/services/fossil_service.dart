import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/catalog_data_source.dart';
import '../models/fossil.dart';
import 'api_client.dart';
import 'token_storage.dart';

class FossilService {
  FossilService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{};
    try {
      final token = await TokenStorage.loadToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // SharedPreferences unavailable in some unit-test environments.
    }
    return headers;
  }

  Future<FossilListResponse> fetchFossils({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    String? dinoQ,
    String? fossilQ,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    bool hasCustomFossilImage = false,
    bool? llmEnriched,
    int? dinosaurId,
    CatalogDataSource dataSource = CatalogDataSource.archive,
    bool includeHidden = false,
  }) async {
    final uri = AppConfig.fossilsUri(
      limit: limit,
      offset: offset,
      sort: sort,
      seed: seed,
      q: q,
      dinoQ: dinoQ,
      fossilQ: fossilQ,
      maYounger: maYounger,
      maOlder: maOlder,
      hasCustomImage: hasCustomImage,
      hasCustomFossilImage: hasCustomFossilImage,
      llmEnriched: llmEnriched,
      dinosaurId: dinosaurId,
      dataSource: dataSource,
      includeHidden: includeHidden,
    );
    if (kDebugMode) {
      debugPrint('FossilService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

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

  Future<FossilListResponse> fetchFossilsForDinosaur(
    int dinosaurId, {
    int limit = 200,
    int offset = 0,
    CatalogDataSource dataSource = CatalogDataSource.archive,
    bool includeHidden = false,
  }) async {
    return fetchFossils(
      limit: limit,
      offset: offset,
      sort: 'random',
      seed: 'dinosaur-$dinosaurId',
      dinosaurId: dinosaurId,
      dataSource: dataSource,
      includeHidden: includeHidden,
    );
  }

  Future<FossilSummary> fetchFossilById(
    int id, {
    CatalogDataSource dataSource = CatalogDataSource.archive,
  }) async {
    final uri = AppConfig.fossilUri(id, dataSource: dataSource);
    if (kDebugMode) {
      debugPrint('FossilService GET $uri');
    }
    final response = await ApiClient.instance
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw FossilServiceException('Fossil not found');
    }
    if (response.statusCode != 200) {
      throw FossilServiceException(
        'Failed to load fossil (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FossilServiceException('Invalid fossil response');
    }
    return FossilSummary.fromJson(decoded);
  }

  Future<FossilSummary> setFossilStatus({
    required int fossilId,
    required String status,
  }) async {
    final uri = AppConfig.fossilStatusUri(fossilId);
    if (kDebugMode) {
      debugPrint('FossilService POST $uri status=$status');
    }
    final response = await ApiClient.instance
        .sendPost(
          uri,
          client: _client,
          headers: {
            ...await _headers(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw FossilServiceException(
        'Failed to set fossil status (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FossilServiceException('Invalid fossil status response');
    }
    return FossilSummary.fromJson(decoded);
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
