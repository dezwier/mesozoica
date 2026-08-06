import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:mesozoica/config/api_endpoints.dart';
import 'package:mesozoica/core/networking/api_transport.dart';
import 'package:mesozoica/models/catalog_data_source.dart';
import 'package:mesozoica/models/fossil.dart';
import 'package:mesozoica/core/networking/api_client.dart';

class FossilService {
  FossilService({http.Client? client, ApiTransport? transport})
    : _client = client ?? http.Client(),
      _transport = transport ?? ApiClient.instance;

  final http.Client _client;
  final ApiTransport _transport;

  Future<Map<String, String>> _headers() async {
    return const {};
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
    final uri = ApiEndpoints.fossilsUri(
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
    final response = await _transport
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
    final uri = ApiEndpoints.fossilUri(id, dataSource: dataSource);
    if (kDebugMode) {
      debugPrint('FossilService GET $uri');
    }
    final response = await _transport
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
    final uri = ApiEndpoints.fossilStatusUri(fossilId);
    if (kDebugMode) {
      debugPrint('FossilService POST $uri status=$status');
    }
    final response = await _transport
        .sendPost(
          uri,
          client: _client,
          headers: {...await _headers(), 'Content-Type': 'application/json'},
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

  Future<void> discardFossil(int fossilId) async {
    final uri = ApiEndpoints.fossilDiscardUri(fossilId);
    if (kDebugMode) {
      debugPrint('FossilService POST $uri');
    }
    final response = await _transport
        .sendPost(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 204) {
      throw FossilServiceException(
        'Failed to discard fossil (${response.statusCode})',
      );
    }
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
