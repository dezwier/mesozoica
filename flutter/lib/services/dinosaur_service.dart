import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/dinosaur.dart';
import '../models/dinosaur_article.dart';
import 'api_client.dart';

class DinosaurService {
  DinosaurService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

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
  }) async {
    final uri = AppConfig.dinosaursUri(
      limit: limit,
      offset: offset,
      sort: sort,
      seed: seed,
      q: q,
      maYounger: maYounger,
      maOlder: maOlder,
      hasCustomImage: hasCustomImage,
      llmEnriched: llmEnriched,
    );
    if (kDebugMode) {
      debugPrint('DinosaurService GET $uri');
    }
    final response = await ApiClient.instance.sendGet(uri, client: _client).timeout(const Duration(seconds: 15));

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
    final uri = AppConfig.dinosaurUri(id);
    if (kDebugMode) {
      debugPrint('DinosaurService GET $uri');
    }
    final response =
        await ApiClient.instance.sendGet(uri, client: _client).timeout(const Duration(seconds: 15));

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
    final uri = AppConfig.dinosaurArticleUri(id);
    final response =
        await ApiClient.instance.sendGet(uri, client: _client).timeout(const Duration(seconds: 20));

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
