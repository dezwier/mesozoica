import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../controllers/aerial_mission_controller.dart';
import '../../models/aerial_mission_kind.dart';
import '../../models/site_map_filters.dart';
import '../../services/auth_service.dart';
import '../../services/token_storage.dart';
import '../../services/tool_service.dart';

const double _scoutPuckLogicalSize = 28;
const double _scoutPuckPixelRatio = 3;
const String _scoutPuckFallbackAsset = 'assets/images/logo.png';

/// Active missions always; past only when [showPastAerialRoutes] and within 24h.
List<AerialMission> aerialMissionsForMap({
  required List<AerialMission> missions,
  required bool showPastAerialRoutes,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now().toUtc();
  return [
    for (final mission in missions)
      if (mission.isActive)
        mission
      else if (showPastAerialRoutes &&
          mission.isPast &&
          _pastAerialRouteIsRecent(mission, clock))
        mission,
  ];
}

bool _pastAerialRouteIsRecent(AerialMission mission, DateTime now) {
  final end = mission.flightEndsAt ?? mission.createdAt;
  final age = now.difference(end);
  return age.isNegative || age <= pastAerialRouteMaxAge;
}

/// Mapbox polylines + scout pucks for aerial recon missions.
class MapboxAerialMissionAnnotations {
  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _scoutManager;
  Cancelable? _tapCancelable;
  void Function(int missionId)? _onScoutTap;
  Uint8List? _cachedPuckPng;
  String? _cachedPuckKey;
  String? _lastRouteSignature;
  final Map<int, PointAnnotation> _scoutsByMissionId = {};
  int _syncSeq = 0;
  bool _scoutUpdateInFlight = false;
  bool _scoutUpdateQueued = false;
  AerialMissionController? _pendingScoutController;

  Future<void> attach({
    required PolylineAnnotationManager lineManager,
    required PointAnnotationManager scoutManager,
    void Function(int missionId)? onScoutTap,
  }) async {
    _lineManager = lineManager;
    _scoutManager = scoutManager;
    _onScoutTap = onScoutTap;
    _tapCancelable?.cancel();
    _tapCancelable = scoutManager.tapEvents(onTap: _handleScoutTap);
  }

  void _handleScoutTap(PointAnnotation annotation) {
    final onTap = _onScoutTap;
    if (onTap == null) return;
    final missionId = _missionIdFromCustomData(annotation.customData);
    if (missionId == null) return;
    onTap(missionId);
  }

  Future<void> sync(
    AerialMissionController controller, {
    required bool showPastAerialRoutes,
  }) async {
    final lineManager = _lineManager;
    final scoutManager = _scoutManager;
    if (lineManager == null || scoutManager == null) return;

    final seq = ++_syncSeq;
    final missions = aerialMissionsForMap(
      missions: controller.missions,
      showPastAerialRoutes: showPastAerialRoutes,
    );
    final routeSignature =
        '${showPastAerialRoutes ? 1 : 0}|${_routeSignature(missions)}';

    Uint8List? puckImage;
    final needsScout = missions.any((m) => m.isFlying || m.isEnsuring);
    if (needsScout) {
      final scoutMission =
          missions.firstWhere((m) => m.isFlying || m.isEnsuring);
      final imageUrl = AuthService.imageUrl(scoutMission.toolImageUrl);
      final accent = AerialMissionKind.fromActionKey(
        scoutMission.actionKey,
      ).activeRouteColor;
      puckImage = await _puckPng(imageUrl, accent: accent);
      if (seq != _syncSeq) return;
    }

    if (routeSignature != _lastRouteSignature) {
      _lastRouteSignature = routeSignature;
      final lineOptions = <PolylineAnnotationOptions>[];
      for (final mission in missions) {
        if (mission.route.length < 2) continue;
        final active = mission.isActive;
        final kind = AerialMissionKind.fromActionKey(mission.actionKey);
        lineOptions.add(
          PolylineAnnotationOptions(
            geometry: LineString(
              coordinates: [
                for (final p in mission.route)
                  Position(p.longitude, p.latitude),
              ],
            ),
            lineColor: active ? kind.activeRouteArgb : kind.pastRouteArgb,
            lineWidth: active ? 4.0 : 3.0,
            lineOpacity: active ? 0.95 : 0.55,
            lineSortKey: active ? 2.0 : 1.0,
          ),
        );
      }
      await lineManager.deleteAll();
      if (seq != _syncSeq) return;
      if (lineOptions.isNotEmpty) {
        await lineManager.createMulti(lineOptions);
      }
      if (seq != _syncSeq) return;
    }

    await _syncScouts(
      controller: controller,
      scoutManager: scoutManager,
      puckImage: puckImage,
      seq: seq,
    );
  }

  Future<void> _syncScouts({
    required AerialMissionController controller,
    required PointAnnotationManager scoutManager,
    required Uint8List? puckImage,
    required int seq,
  }) async {
    if (_scoutUpdateInFlight) {
      _scoutUpdateQueued = true;
      _pendingScoutController = controller;
      return;
    }
    _scoutUpdateInFlight = true;
    try {
      do {
        _scoutUpdateQueued = false;
        final now = DateTime.now().toUtc();
        final activeIds = <int>{};
        final updates = <Future<void>>[];

        for (final mission in controller.missions) {
          if (!(mission.isFlying || mission.isEnsuring)) continue;
          final pos = controller.scoutPosition(mission, now: now);
          if (pos == null) continue;
          final bearing = controller.scoutBearing(mission, now: now);
          activeIds.add(mission.missionId);

          final existing = _scoutsByMissionId[mission.missionId];
          if (existing != null) {
            existing.geometry = Point(
              coordinates: Position(pos.longitude, pos.latitude),
            );
            existing.iconRotate = bearing;
            updates.add(scoutManager.update(existing));
          } else if (puckImage != null) {
            updates.add(() async {
              final created = await scoutManager.create(
                PointAnnotationOptions(
                  geometry: Point(
                    coordinates: Position(pos.longitude, pos.latitude),
                  ),
                  image: puckImage,
                  iconSize: 1.0,
                  iconRotate: bearing,
                  iconAnchor: IconAnchor.CENTER,
                  symbolSortKey: 10,
                  customData: {'missionId': '${mission.missionId}'},
                ),
              );
              if (seq != _syncSeq) return;
              _scoutsByMissionId[mission.missionId] = created;
            }());
          }
        }

        for (final id in _scoutsByMissionId.keys.toList()) {
          if (activeIds.contains(id)) continue;
          final stale = _scoutsByMissionId.remove(id);
          if (stale != null) {
            updates.add(scoutManager.delete(stale));
          }
        }

        if (updates.isNotEmpty) await Future.wait(updates);
        if (seq != _syncSeq) return;

        if (_scoutUpdateQueued) {
          controller = _pendingScoutController ?? controller;
          _pendingScoutController = null;
        }
      } while (_scoutUpdateQueued && seq == _syncSeq);
    } finally {
      _scoutUpdateInFlight = false;
    }
  }

  Future<void> clear() async {
    _syncSeq++;
    _lastRouteSignature = null;
    _scoutsByMissionId.clear();
    await _lineManager?.deleteAll();
    await _scoutManager?.deleteAll();
  }

  void dispose() {
    _syncSeq++;
    _lastRouteSignature = null;
    _scoutsByMissionId.clear();
    _tapCancelable?.cancel();
    _tapCancelable = null;
    _onScoutTap = null;
    _lineManager = null;
    _scoutManager = null;
  }

  String _routeSignature(List<AerialMission> missions) {
    final buf = StringBuffer();
    for (final mission in missions) {
      buf
        ..write(mission.missionId)
        ..write(':')
        ..write(mission.actionKey)
        ..write(':')
        ..write(mission.status)
        ..write(':')
        ..write(mission.route.length)
        ..write(';');
    }
    return buf.toString();
  }

  static int? _missionIdFromCustomData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['missionId'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<Uint8List> _puckPng(String imageUrl, {required Color accent}) async {
    final key = '$imageUrl|${accent.toARGB32()}';
    if (_cachedPuckPng != null && _cachedPuckKey == key) {
      return _cachedPuckPng!;
    }
    final avatar = await _loadAvatar(imageUrl);
    try {
      final png = await _renderScoutPuckPng(avatar: avatar, accent: accent);
      _cachedPuckPng = png;
      _cachedPuckKey = key;
      return png;
    } finally {
      avatar?.dispose();
    }
  }
}

Future<ui.Image?> _loadAvatar(String imageUrl) async {
  if (imageUrl.isNotEmpty) {
    final cached = await _imageFromProvider(
      CachedNetworkImageProvider(imageUrl),
    );
    if (cached != null) return cached;
    try {
      final token = await TokenStorage.loadToken();
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return _decodeUiImage(response.bodyBytes);
      }
    } catch (_) {}
  }
  try {
    final data = await rootBundle.load(_scoutPuckFallbackAsset);
    return _decodeUiImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

Future<ui.Image?> _imageFromProvider(ImageProvider provider) async {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(info.image.clone());
      }
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(
    const Duration(seconds: 8),
    onTimeout: () {
      stream.removeListener(listener);
      return null;
    },
  );
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> _renderScoutPuckPng({
  ui.Image? avatar,
  required Color accent,
}) async {
  const pixelRatio = _scoutPuckPixelRatio;
  final circleSpan = (_scoutPuckLogicalSize * pixelRatio).round().clamp(48, 160);
  final radius = circleSpan / 2 - pixelRatio * 2;
  final outerPad = radius * 0.55;
  final dim = (circleSpan + 2 * outerPad).round();
  final center = Offset(dim / 2, dim / 2);
  final borderWidth = 2.5 * pixelRatio;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawCircle(
    center.translate(0, pixelRatio * 1.2),
    radius,
    Paint()
      ..color = const Color(0x66000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio * 1.4),
  );

  final innerRadius = radius - borderWidth / 2;
  canvas.drawCircle(center, innerRadius, Paint()..color = Colors.white);

  canvas.save();
  canvas.clipPath(
    ui.Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius)),
  );
  if (avatar != null) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromCircle(center: center, radius: innerRadius),
      image: avatar,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      isAntiAlias: true,
    );
  }
  canvas.restore();

  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth,
  );

  final height = radius * 0.4;
  final halfWidth = radius * 0.3;
  final baseY = center.dy - radius;
  final tip = Offset(center.dx, baseY - height);
  final path = ui.Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(tip.dx + halfWidth, baseY)
    ..lineTo(tip.dx - halfWidth, baseY)
    ..close();
  canvas.drawPath(
    path,
    Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pixelRatio * 0.7),
  );
  canvas.drawPath(path, Paint()..color = accent);
  canvas.drawPath(
    path,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * pixelRatio
      ..strokeJoin = StrokeJoin.round,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(dim, dim);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) {
    throw StateError('Failed to encode aerial recon scout puck PNG');
  }
  return bytes.buffer.asUint8List();
}
