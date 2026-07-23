import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../models/tool.dart';
import '../services/tool_service.dart';

/// Client state for Aerial Recon draw mode and mission submit.
class AerialReconController extends ChangeNotifier {
  AerialReconController({ToolService? toolService})
      : _toolService = toolService ?? ToolService();

  final ToolService _toolService;
  final Distance _distance = const Distance();

  bool _drawMode = false;
  ToolSummary? _tool;
  final List<LatLng> _route = [];
  bool _drawing = false;
  bool _submitting = false;
  String? _message;

  bool get isDrawMode => _drawMode;
  ToolSummary? get tool => _tool;
  List<LatLng> get route => List.unmodifiable(_route);
  bool get isDrawing => _drawing;
  bool get isSubmitting => _submitting;
  String? get message => _message;
  bool get hasRoute => _route.length >= 2;

  AerialReconActionConfig get _cfg =>
      GameConfig.instance.toolActions.aerialRecon;

  double get maxRouteKm => _cfg.maxRouteKm;
  double get loopEndpointToleranceM => _cfg.loopEndpointToleranceM;

  double routeLengthKm() {
    if (_route.length < 2) return 0;
    var metres = 0.0;
    for (var i = 1; i < _route.length; i++) {
      metres += _distance(_route[i - 1], _route[i]);
    }
    return metres / 1000.0;
  }

  void beginDraw(ToolSummary tool) {
    _tool = tool;
    _drawMode = true;
    _route.clear();
    _drawing = false;
    _submitting = false;
    _message = 'Draw a loop that starts and ends at your location';
    notifyListeners();
  }

  void cancelDraw() {
    _drawMode = false;
    _tool = null;
    _route.clear();
    _drawing = false;
    _submitting = false;
    _message = null;
    notifyListeners();
  }

  void clearRoute({String? message}) {
    _route.clear();
    _drawing = false;
    _message = message;
    notifyListeners();
  }

  void startStroke(LatLng point) {
    if (!_drawMode || _submitting) return;
    _route
      ..clear()
      ..add(point);
    _drawing = true;
    _message = null;
    notifyListeners();
  }

  void appendPoint(LatLng point, {double minSpacingM = 25}) {
    if (!_drawMode || !_drawing || _submitting) return;
    if (_route.isEmpty) {
      _route.add(point);
      notifyListeners();
      return;
    }
    final last = _route.last;
    if (_distance(last, point) < minSpacingM) return;
    _route.add(point);
    notifyListeners();
  }

  void endStroke() {
    if (!_drawing) return;
    _drawing = false;
    notifyListeners();
  }

  /// Validate closed loop against [origin]; clear + message on failure.
  bool validateAgainstOrigin(LatLng? origin) {
    if (origin == null) {
      clearRoute(message: 'Waiting for your current location');
      return false;
    }
    if (_route.length < 3) {
      clearRoute(message: 'Draw a longer loop, then tap Finish');
      return false;
    }

    final startM = _distance(origin, _route.first);
    final endM = _distance(origin, _route.last);
    if (startM > loopEndpointToleranceM || endM > loopEndpointToleranceM) {
      clearRoute(
        message:
            'Loop must start and end at your location. Try drawing again.',
      );
      return false;
    }

    final lengthKm = routeLengthKm();
    if (lengthKm > maxRouteKm) {
      clearRoute(
        message:
            'Loop was ${lengthKm.toStringAsFixed(1)} km; '
            'maximum allowed is ${maxRouteKm.toStringAsFixed(0)} km.',
      );
      return false;
    }
    return true;
  }

  Future<bool> submit({required LatLng origin}) async {
    final tool = _tool;
    if (tool == null || _submitting) return false;
    if (!validateAgainstOrigin(origin)) return false;

    _submitting = true;
    _message = 'Deploying Aerial Recon…';
    notifyListeners();

    try {
      await _toolService.startAerialRecon(
        toolId: tool.id,
        route: List<LatLng>.from(_route),
        origin: origin,
      );
      cancelDraw();
      return true;
    } on ToolServiceException catch (error) {
      _message = error.message;
      _submitting = false;
      notifyListeners();
      return false;
    } catch (_) {
      _message = 'Failed to deploy Aerial Recon';
      _submitting = false;
      notifyListeners();
      return false;
    }
  }
}
