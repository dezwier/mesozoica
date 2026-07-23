import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../controllers/aerial_recon_controller.dart';
import '../../services/auth_service.dart';
import '../../services/token_storage.dart';
import '../../services/tool_service.dart';
import '../../utils/route_geometry.dart';

const Color _reconGold = Color(0xFFD4AF37);
const int _reconGoldArgb = 0xFFD4AF37;
const double _scoutPuckLogicalSize = 28;
const double _scoutPuckPixelRatio = 3;
const String _scoutPuckFallbackAsset = 'assets/images/logo.png';

/// Mapbox polylines + scout pucks for aerial recon missions.
class MapboxAerialReconAnnotations {
  PolylineAnnotationManager? _lineManager;
  PointAnnotationManager? _scoutManager;
  Cancelable? _tapCancelable;
  void Function(int missionId)? _onScoutTap;
  Uint8List? _cachedPuckPng;
  String? _cachedPuckKey;
  String? _lastRouteSignature;
  int _syncSeq = 0;

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

  Future<void> sync(AerialReconController controller) async {
    final lineManager = _lineManager;
    final scoutManager = _scoutManager;
    if (lineManager == null || scoutManager == null) return;

    final seq = ++_syncSeq;
    final missions = controller.missions;
    final now = DateTime.now().toUtc();
    final routeSignature = _routeSignature(missions, now: now);

    Uint8List? puckImage;
    final needsScout = missions.any((m) => m.isFlying || m.isEnsuring);
    if (needsScout) {
      final imageUrl = AuthService.imageUrl(
        missions
            .firstWhere((m) => m.isFlying || m.isEnsuring)
            .toolImageUrl,
      );
      puckImage = await _puckPng(imageUrl);
      if (seq != _syncSeq) return;
    }

    if (routeSignature != _lastRouteSignature) {
      _lastRouteSignature = routeSignature;
      final lineOptions = <PolylineAnnotationOptions>[];
      for (final mission in missions) {
        if (mission.route.length < 2) continue;
        if (mission.isActive) {
          final frac = aerialReconProgressFraction(mission, now: now);
          _appendProgressLines(lineOptions, mission.route, frac);
        } else {
          lineOptions.add(
            PolylineAnnotationOptions(
              geometry: LineString(
                coordinates: [
                  for (final p in mission.route)
                    Position(p.longitude, p.latitude),
                ],
              ),
              lineColor: _reconGoldArgb,
              lineWidth: 3.0,
              lineOpacity: 0.38,
              lineSortKey: 1.0,
            ),
          );
        }
      }
      await lineManager.deleteAll();
      if (seq != _syncSeq) return;
      if (lineOptions.isNotEmpty) {
        await lineManager.createMulti(lineOptions);
      }
      if (seq != _syncSeq) return;
    }

    final scoutOptions = <PointAnnotationOptions>[];
    if (puckImage != null) {
      for (final mission in missions) {
        if (!(mission.isFlying || mission.isEnsuring)) continue;
        final pos = controller.scoutPosition(mission, now: now);
        if (pos == null) continue;
        final bearing = controller.scoutBearing(mission, now: now);
        scoutOptions.add(
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
      }
    }

    await scoutManager.deleteAll();
    if (seq != _syncSeq) return;
    if (scoutOptions.isNotEmpty) {
      await scoutManager.createMulti(scoutOptions);
    }
  }

  void _appendProgressLines(
    List<PolylineAnnotationOptions> lineOptions,
    List<LatLng> route,
    double frac,
  ) {
    final done = RouteGeometry.prefixUpToFraction(route, frac);
    final todo = RouteGeometry.suffixFromFraction(route, frac);

    if (todo.length >= 2) {
      lineOptions.add(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: [
              for (final p in todo) Position(p.longitude, p.latitude),
            ],
          ),
          lineColor: _reconGoldArgb,
          lineWidth: 3.0,
          lineOpacity: 0.5,
          lineSortKey: 2.0,
        ),
      );
    }
    if (done.length >= 2) {
      lineOptions.add(
        PolylineAnnotationOptions(
          geometry: LineString(
            coordinates: [
              for (final p in done) Position(p.longitude, p.latitude),
            ],
          ),
          lineColor: _reconGoldArgb,
          lineWidth: 5.5,
          lineOpacity: 0.95,
          lineSortKey: 3.0,
        ),
      );
    }
  }

  Future<void> clear() async {
    _syncSeq++;
    _lastRouteSignature = null;
    await _lineManager?.deleteAll();
    await _scoutManager?.deleteAll();
  }

  void dispose() {
    _syncSeq++;
    _lastRouteSignature = null;
    _tapCancelable?.cancel();
    _tapCancelable = null;
    _onScoutTap = null;
    _lineManager = null;
    _scoutManager = null;
  }

  String _routeSignature(List<AerialReconMission> missions, {required DateTime now}) {
    final buf = StringBuffer();
    for (final mission in missions) {
      buf
        ..write(mission.missionId)
        ..write(':')
        ..write(mission.status)
        ..write(':')
        ..write(mission.route.length);
      if (mission.isActive) {
        final frac = aerialReconProgressFraction(mission, now: now);
        // Quantize so the split stroke updates about once per percent.
        buf
          ..write(':')
          ..write((frac * 100).round());
      }
      buf.write(';');
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

  Future<Uint8List> _puckPng(String imageUrl) async {
    final key = imageUrl;
    if (_cachedPuckPng != null && _cachedPuckKey == key) {
      return _cachedPuckPng!;
    }
    final avatar = await _loadAvatar(imageUrl);
    try {
      final png = await _renderScoutPuckPng(avatar: avatar);
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

Future<Uint8List> _renderScoutPuckPng({ui.Image? avatar}) async {
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
  canvas.drawPath(path, Paint()..color = _reconGold);
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
