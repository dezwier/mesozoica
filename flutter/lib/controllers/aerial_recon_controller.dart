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
  bool _confirming = false;
  ToolSummary? _tool;
  final List<LatLng> _route = [];
  bool _drawing = false;
  bool _submitting = false;
  String? _message;

  bool get isDrawMode => _drawMode;
  bool get isConfirming => _confirming;
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
    _confirming = false;
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
    _confirming = false;
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
    _confirming = false;
    _message = message;
    notifyListeners();
  }

  /// Leave confirm and draw again (keeps mode open).
  void redraw() {
    if (!_drawMode || _submitting) return;
    _route.clear();
    _drawing = false;
    _confirming = false;
    _message =
        'Draw with one finger; pinch to zoom. '
        'The loop starts and ends at your location. '
        'Allowed range: up to ${_formatKm(maxRouteKm)}.';
    notifyListeners();
  }

  /// Abort an in-progress stroke (e.g. second finger / pinch started).
  void abortStroke() {
    if (!_drawMode || _confirming || _submitting) return;
    if (!_drawing && _route.isEmpty) return;
    _route.clear();
    _drawing = false;
    _message =
        'Draw with one finger; pinch to zoom. '
        'The loop starts and ends at your location. '
        'Allowed range: up to ${_formatKm(maxRouteKm)}.';
    notifyListeners();
  }

  /// Begin a stroke anchored at [origin] (current location).
  void startStroke(LatLng fingerPoint, {required LatLng? origin}) {
    if (!_drawMode || _submitting || _confirming) return;
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
    if (!_drawMode || !_drawing || _submitting || _confirming) return;
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

  /// Validate and enter confirm step. Clears the stroke on failure.
  bool finishDrawing(LatLng? origin) {
    if (_confirming || _submitting) return false;
    if (origin == null) {
      clearRoute(message: 'Waiting for your current location');
      return false;
    }
    _snapEndpointsToOrigin(origin);
    _drawing = false;

    final error = validationError(origin);
    if (error != null) {
      clearRoute(message: error);
      return false;
    }
    _confirming = true;
    _message = null;
    notifyListeners();
    return true;
  }

  /// Returns an error message, or null when the route is valid.
  String? validationError(LatLng? origin) {
    if (origin == null) {
      return 'Waiting for your current location';
    }
    if (_route.length < 3) {
      return 'Draw a longer loop, then tap Finish';
    }

    final lengthKm = routeLengthKm();
    if (lengthKm > maxRouteKm) {
      return 'Loop was ${lengthKm.toStringAsFixed(1)} km; '
          'maximum allowed is ${_formatKm(maxRouteKm)}.';
    }
    return null;
  }

  Future<bool> confirmAndSubmit({required LatLng origin}) async {
    final tool = _tool;
    if (tool == null || !_confirming || _submitting) return false;
    _snapEndpointsToOrigin(origin);
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
