import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/game_config.dart';

/// Loads the shared game-config control board at startup.
///
/// The backend (`GET /api/v1/game-config`) is the source of truth. Resolution
/// order (first that succeeds wins):
///   1. Backend API — current, live config.
///   2. Last-good copy cached on device — survives offline / backend-down launches.
///   3. Bundled canonical snapshot (`assets/game_config.json`) — generated from
///      the backend control board by `scripts/export_bundled_game_config`.
///   4. Bundled YAML control board — last-resort belt-and-suspenders fallback.
///
/// Because a bundled fallback is always present, the worst case still yields a
/// working config, so a backend outage can never block startup. The parsed
/// result is exposed through the unchanged [GameConfig.instance] accessor, so no
/// call sites change.
class GameConfigService {
  GameConfigService._();

  static final GameConfigService instance = GameConfigService._();

  static const String _cacheKey = 'game_config_payload_v1';
  static const String _bundledSnapshotAsset = 'assets/game_config.json';
  static const Duration _fetchTimeout = Duration(seconds: 8);

  String? _loadedVersion;
  String? _loadedSource;

  /// Content version of the loaded config (null when bundled fallback was used).
  String? get loadedVersion => _loadedVersion;

  /// Where the active config came from: `api`, `cache`, or `bundled`.
  String? get loadedSource => _loadedSource;

  /// Resolve config from network → device cache → bundled snapshot → YAML.
  Future<void> initialize() async {
    if (await _loadFromNetwork()) return;
    if (await _loadFromCache()) return;
    if (await _loadFromBundledSnapshot()) return;
    await GameConfig.load(); // last-resort YAML control board
    _loadedVersion = null;
    _loadedSource = 'bundled-yaml';
    if (kDebugMode) {
      debugPrint('GameConfig: loaded from bundled YAML (last-resort fallback)');
    }
  }

  Future<bool> _loadFromNetwork() async {
    try {
      final response =
          await http.get(AppConfig.gameConfigUri).timeout(_fetchTimeout);
      if (response.statusCode != 200) return false;
      if (!_applyPayloadJson(response.body)) return false;
      await _cachePayload(response.body);
      _loadedSource = 'api';
      if (kDebugMode) {
        debugPrint('GameConfig: loaded from API (version=$_loadedVersion)');
      }
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('GameConfig: API fetch failed: $error');
      return false;
    }
  }

  Future<bool> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached == null) return false;
      if (!_applyPayloadJson(cached)) return false;
      _loadedSource = 'cache';
      if (kDebugMode) {
        debugPrint('GameConfig: loaded from device cache '
            '(version=$_loadedVersion)');
      }
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('GameConfig: cache load failed: $error');
      return false;
    }
  }

  Future<bool> _loadFromBundledSnapshot() async {
    try {
      final raw = await rootBundle.loadString(_bundledSnapshotAsset);
      if (!_applyPayloadJson(raw)) return false;
      _loadedSource = 'bundled-snapshot';
      if (kDebugMode) {
        debugPrint('GameConfig: loaded from bundled snapshot '
            '(version=$_loadedVersion)');
      }
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('GameConfig: bundled snapshot load failed: $error');
      }
      return false;
    }
  }

  /// Parse a `{version, config}` payload and install it as the active config.
  /// Returns false (without mutating the singleton) on malformed payloads.
  bool _applyPayloadJson(String rawBody) {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) return false;
    final config = decoded['config'];
    if (config is! Map<String, dynamic>) return false;
    GameConfig.fromSections(config);
    _loadedVersion = decoded['version'] as String?;
    return true;
  }

  Future<void> _cachePayload(String rawBody) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, rawBody);
    } catch (_) {
      // Caching is best-effort; a failure here must not break startup.
    }
  }
}
