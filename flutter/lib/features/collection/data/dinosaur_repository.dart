import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:mesozoica/config/api_endpoints.dart';
import 'package:mesozoica/core/networking/api_transport.dart';
import 'package:mesozoica/models/dinosaur.dart';
import 'package:mesozoica/models/dinosaur_article.dart';
import 'package:mesozoica/core/networking/api_client.dart';

class DinosaurService {
  DinosaurService({http.Client? client, ApiTransport? transport})
    : _client = client ?? http.Client(),
      _transport = transport ?? ApiClient.instance;

  final http.Client _client;
  final ApiTransport _transport;

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    return jsonBody ? const {'Content-Type': 'application/json'} : const {};
  }

  Future<DinosaurListResponse> fetchDinosaurs({
    int limit = 200,
    int offset = 0,
    String sort = 'name',
    String? seed,
    String? q,
    double? maYounger,
    double? maOlder,
    bool hasCustomImage = false,
    bool? llmEnriched,
    Set<String> diets = const {},
    double? lengthMMin,
    double? lengthMMax,
    double? massKgMin,
    double? massKgMax,
    String mode = 'inventory',
  }) async {
    final uri = ApiEndpoints.dinosaursUri(
      limit: limit,
      offset: offset,
      sort: sort,
      seed: seed,
      q: q,
      maYounger: maYounger,
      maOlder: maOlder,
      hasCustomImage: hasCustomImage,
      llmEnriched: llmEnriched,
      diets: diets,
      lengthMMin: lengthMMin,
      lengthMMax: lengthMMax,
      massKgMin: massKgMin,
      massKgMax: massKgMax,
      mode: mode,
    );
    if (kDebugMode) {
      debugPrint('DinosaurService GET $uri');
    }
    final response = await _transport
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw DinosaurServiceException(
        'Failed to load dinosaurs (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const DinosaurServiceException('Invalid dinosaurs response');
    }
    return DinosaurListResponse.fromJson(decoded);
  }

  Future<DinosaurSummary> fetchDinosaurById(int id) async {
    final uri = ApiEndpoints.dinosaurUri(id);
    if (kDebugMode) {
      debugPrint('DinosaurService GET $uri');
    }
    final response = await _transport
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw DinosaurServiceException('Dinosaur not found');
    }
    if (response.statusCode != 200) {
      throw DinosaurServiceException(
        'Failed to load dinosaur (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const DinosaurServiceException('Invalid dinosaur response');
    }
    return DinosaurSummary.fromJson(decoded);
  }

  Future<DinosaurArticle> fetchDinosaurArticle(int id) async {
    final uri = ApiEndpoints.dinosaurArticleUri(id);
    final response = await _transport
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 404) {
      throw DinosaurServiceException('Dinosaur article not found');
    }
    if (response.statusCode != 200) {
      throw DinosaurServiceException(
        'Failed to load dinosaur article (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const DinosaurServiceException('Invalid dinosaur article response');
    }
    return DinosaurArticle.fromJson(decoded);
  }

  Future<List<String>> listDinosaurImageVersions() async {
    final uri = ApiEndpoints.dinosaurImageVersionsUri();
    if (kDebugMode) {
      debugPrint('DinosaurService GET $uri');
    }
    final response = await _transport
        .sendGet(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw DinosaurServiceException(
        'Failed to load dinosaur image versions (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const DinosaurServiceException(
        'Invalid dinosaur image versions response',
      );
    }
    final items = decoded['items'];
    if (items is! List) {
      throw const DinosaurServiceException(
        'Invalid dinosaur image versions items',
      );
    }
    final names = <String>[];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final name = (item['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          names.add(name);
        }
      }
    }
    return names;
  }

  Future<DinosaurSummary> collectDinosaur({
    required int dinosaurTypeId,
    required String status,
    required String version,
  }) async {
    final uri = ApiEndpoints.dinosaurCollectUri(dinosaurTypeId);
    if (kDebugMode) {
      debugPrint('DinosaurService POST $uri status=$status version=$version');
    }
    final response = await _transport
        .sendPost(
          uri,
          client: _client,
          headers: await _headers(jsonBody: true),
          body: jsonEncode({'status': status, 'version': version}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw DinosaurServiceException(
        'Failed to collect dinosaur (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const DinosaurServiceException('Invalid dinosaur collect response');
    }
    return DinosaurSummary.fromJson(decoded);
  }

  Future<void> discardDinosaur(int dinosaurId) async {
    final uri = ApiEndpoints.dinosaurDiscardUri(dinosaurId);
    if (kDebugMode) {
      debugPrint('DinosaurService POST $uri');
    }
    final response = await _transport
        .sendPost(uri, client: _client, headers: await _headers())
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 204) {
      throw DinosaurServiceException(
        'Failed to discard dinosaur (${response.statusCode})',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

class DinosaurServiceException implements Exception {
  const DinosaurServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
