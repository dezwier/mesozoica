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
  double get shortRouteWarnFraction => _cfg.shortRouteWarnFraction;

  double routeLengthKm() {
    if (_route.length < 2) return 0;
    var metres = 0.0;
    for (var i = 1; i < _route.length; i++) {
      metres += _distance(_route[i - 1], _route[i]);
    }
    return metres / 1000.0;
  }

  bool get isShortRoute {
    if (maxRouteKm <= 0) return false;
    return routeLengthKm() < maxRouteKm * shortRouteWarnFraction;
  }

  String get rangeHint {
    final maxLabel = maxRouteKm == maxRouteKm.roundToDouble()
        ? maxRouteKm.toStringAsFixed(0)
        : maxRouteKm.toStringAsFixed(1);
    final drawn = routeLengthKm();
    if (drawn <= 0) {
      return 'Allowed range: up to $maxLabel km';
    }
    return 'Drawn ${drawn.toStringAsFixed(1)} km · allowed up to $maxLabel km';
  }

  void beginDraw(ToolSummary tool) {
    _tool = tool;
    _drawMode = true;
    _route.clear();
    _drawing = false;
    _submitting = false;
    _message =
        'Draw with one finger; pinch to zoom. '
        'The loop starts and ends at your location. '
        'Allowed range: up to ${_formatKm(maxRouteKm)}.';
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

  /// Reset the drawn route; stay in draw mode.
  void clearDrawnRoute() {
    if (!_drawMode || _submitting) return;
    _route.clear();
    _drawing = false;
    _message =
        'Draw with one finger; pinch to zoom. '
        'The loop starts and ends at your location. '
        'Allowed range: up to ${_formatKm(maxRouteKm)}.';
    notifyListeners();
  }

  /// Pause an in-progress stroke without clearing or closing it (e.g. pinch).
  void pauseStroke() {
    if (!_drawing) return;
    _drawing = false;
    notifyListeners();
  }

  /// Resume appending to an existing unfinished stroke after a pinch.
  void resumeStroke() {
    if (!_drawMode || _submitting) return;
    if (_route.isEmpty) return;
    _drawing = true;
    _message = null;
    notifyListeners();
  }

  /// Begin a stroke anchored at [origin] (current location).
  void startStroke(LatLng fingerPoint, {required LatLng? origin}) {
    if (!_drawMode || _submitting) return;
    if (origin == null) {
      _message = 'Waiting for your current location';
      notifyListeners();
      return;
    }
    _route
      ..clear()
      ..add(origin);
    if (_distance(origin, fingerPoint) >= 25) {
      _route.add(fingerPoint);
    }
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

  /// End stroke and snap the route closed on [origin].
  void endStroke({LatLng? origin}) {
    if (!_drawing) return;
    if (origin != null) {
      _snapEndpointsToOrigin(origin);
    }
    _drawing = false;
    notifyListeners();
  }

  /// Returns an error message, or null when the route is valid.
  String? validationError(LatLng? origin) {
    if (origin == null) {
      return 'Waiting for your current location';
    }
    if (_route.length < 3) {
      return 'Draw a longer loop, then tap Deploy Recon';
    }

    final lengthKm = routeLengthKm();
    if (lengthKm > maxRouteKm) {
      return 'Loop was ${lengthKm.toStringAsFixed(1)} km; '
          'maximum allowed is ${_formatKm(maxRouteKm)}.';
    }
    return null;
  }

  /// Validate and submit the scout mission.
  Future<bool> deployRecon({required LatLng origin}) async {
    final tool = _tool;
    if (tool == null || !_drawMode || _submitting) return false;

    _snapEndpointsToOrigin(origin);
    _drawing = false;

    final error = validationError(origin);
    if (error != null) {
      clearRoute(message: error);
      return false;
    }

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

  void _snapEndpointsToOrigin(LatLng origin) {
    if (_route.isEmpty) {
      _route.add(origin);
      return;
    }
    _route[0] = origin;
    if (_route.length == 1) {
      return;
    }
    if (_distance(_route.last, origin) < 5) {
      _route[_route.length - 1] = origin;
    } else {
      _route.add(origin);
    }
  }

  static String _formatKm(double km) {
    if (km == km.roundToDouble()) return '${km.toStringAsFixed(0)} km';
    return '${km.toStringAsFixed(1)} km';
  }
}
