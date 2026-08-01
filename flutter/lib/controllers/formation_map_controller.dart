import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../controllers/field_discovery_coordinator.dart';
import '../models/formation_map_kind.dart';
import '../models/site.dart';
import '../models/tool.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';
import '../services/tool_service.dart';
import '../utils/survey_grid.dart';

/// Active timed Formation Map session (fixed rock-type square overlay).
///
/// May top up field sites at the locked map center using the same global ensure
/// knobs as walk-around ensure ([SiteGenerationClientConfig.nearbyRadiusKm] /
/// backend `max_sites_per_cell` / `cell_size_m`) — never the Formation Map footprint size.
class FormationMapController extends ChangeNotifier {
  FormationMapController({
    ToolService? toolService,
    SiteService? siteService,
  })  : _toolService = toolService ?? ToolService(),
        _siteService = siteService ?? SiteService();

  final ToolService _toolService;
  final SiteService _siteService;

  FieldDiscoveryCoordinator? _discovery;
  LocationService? _location;
  VoidCallback? _discoveryListener;

  FormationMapSession? _session;
  ToolSummary? _tool;
  bool _activating = false;
  String? _message;
  bool _requestShowOnMap = false;
  Timer? _tickTimer;
  int _sitesRevision = 0;

  final ValueNotifier<Duration?> remainingListenable =
      ValueNotifier<Duration?>(null);

  bool get isActive =>
      _session != null && _session!.isActive && !_session!.isExpired;
  FormationMapSession? get session => _session;
  ToolSummary? get tool => _tool;
  bool get isActivating => _activating;
  String? get message => _message;
  bool get requestShowOnMap => _requestShowOnMap;
  int get sitesRevision => _sitesRevision;
  Duration? get remaining => remainingListenable.value;

  double get accuracy {
    final session = _session;
    if (session != null) return session.accuracy;
    return GameConfig.instance.toolActions.formationMap.accuracy;
  }

  double get widenessM {
    final session = _session;
    if (session != null) return session.widenessM;
    return GameConfig.instance.toolActions.formationMap.resolvedWidenessM;
  }

  double get cellSizeM {
    final session = _session;
    if (session != null) return session.cellSizeM;
    return GameConfig.instance.toolActions.formationMap.cellSizeM;
  }

  LatLng? get center {
    final session = _session;
    if (session == null) return null;
    return LatLng(session.centerLat, session.centerLon);
  }

  GridFootprint? get footprint {
    final c = center;
    if (c == null) return null;
    return footprintForCenter(
      c.latitude,
      c.longitude,
      widenessM: widenessM,
      cellSizeM: cellSizeM,
    );
  }

  List<SiteSummary> get discoverableSites =>
      _discovery?.discoverableCache ?? const [];

  void bind({
    required FieldDiscoveryCoordinator discovery,
    required LocationService location,
  }) {
    if (_discovery == discovery && _location == location) {
      unawaited(restoreActiveSession());
      return;
    }
    _unbindListeners();
    _discovery = discovery;
    _location = location;
    _discoveryListener = _onDiscoveryChanged;
    discovery.addListener(_discoveryListener!);
    unawaited(restoreActiveSession());
  }

  Future<void> restoreActiveSession() async {
    if (_activating) return;
    try {
      final session = await _toolService.fetchActiveFormationMapSession();
      if (session == null || !session.isActive || session.isExpired) {
        if (_session != null && !isActive) {
          await stop(notifyServer: false);
        }
        return;
      }
      if (_session?.sessionId == session.sessionId && isActive) {
        _session = session;
        _ensureTickTimer();
        await _refreshDiscoverableForFootprint(force: false);
        return;
      }
      _session = session;
      _tool = null;
      _ensureTickTimer();
      await _refreshDiscoverableForFootprint(force: true);
      unawaited(_ensureFieldSitesAtMapCenter());
      _message = '${FormationMapKind.toolName} active';
      _bumpSitesRevision();
      notifyListeners();
    } catch (error) {
      debugPrint('Formation map restore failed: $error');
    }
  }

  void consumeShowOnMapRequest() {
    _requestShowOnMap = false;
  }

  Future<void> activate(ToolSummary tool) async {
    if (!tool.isOwned) return;
    if (!FormationMapKind.matchesToolName(tool.name)) return;

    _activating = true;
    _message = null;
    notifyListeners();
    try {
      final loc = _location?.currentLocation;
      final session = await _toolService.startFormationMapSession(
        toolId: tool.id,
        lat: loc?.latitude,
        lon: loc?.longitude,
      );
      _session = session;
      _tool = tool;
      _requestShowOnMap = true;
      _ensureTickTimer();
      await _refreshDiscoverableForFootprint(force: true);
      unawaited(_ensureFieldSitesAtMapCenter());
      _message = '${FormationMapKind.toolName} active';
      _bumpSitesRevision();
    } catch (error) {
      _message = error.toString();
    } finally {
      _activating = false;
      notifyListeners();
    }
  }

  Future<void> stop({bool notifyServer = true}) async {
    _tickTimer?.cancel();
    _tickTimer = null;
    final hadSession = _session != null;
    if (notifyServer && hadSession) {
      try {
        await _toolService.cancelFormationMapSession();
      } catch (_) {}
    }
    _session = null;
    _tool = null;
    _discovery?.setCacheRadiusOverrideKm(null);
    _message = null;
    remainingListenable.value = null;
    _bumpSitesRevision();
    if (hadSession) notifyListeners();
  }

  void clearLocalSession() {
    if (_session == null) return;
    unawaited(stop(notifyServer: false));
  }

  void _onDiscoveryChanged() {
    if (!isActive) return;
    _bumpSitesRevision();
    notifyListeners();
  }

  /// Widen discoverable *fetch* so the square can paint existing sites.
  Future<void> _refreshDiscoverableForFootprint({required bool force}) async {
    final discovery = _discovery;
    final fp = footprint;
    if (discovery == null || !isActive || fp == null) return;
    discovery.setCacheRadiusOverrideKm(fp.halfDiagonalM / 1000.0);
    if (force) {
      await discovery.refreshDiscoverableCache(force: true);
    }
  }

  /// Top up sites at the locked map center with global ensure radius/density.
  Future<void> _ensureFieldSitesAtMapCenter() async {
    final fp = footprint;
    if (fp == null) return;
    final radiusKm =
        GameConfig.instance.siteGeneration.client.nearbyRadiusKm;
    try {
      await _siteService.requestFieldSiteEnsure(
        lat: fp.centerLat,
        lon: fp.centerLon,
        radiusKm: radiusKm,
        reason: 'formation_map',
      );
      await _discovery?.refreshDiscoverableCache(force: true);
      _bumpSitesRevision();
      notifyListeners();
    } catch (error) {
      debugPrint('Formation map ensure failed: $error');
    }
  }

  void _ensureTickTimer() {
    _tickTimer?.cancel();
    _syncRemaining();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!isActive) {
        unawaited(stop(notifyServer: false));
        return;
      }
      _syncRemaining();
    });
  }

  void _syncRemaining() {
    final expires = _session?.expiresAt;
    if (expires == null) {
      if (remainingListenable.value != null) {
        remainingListenable.value = null;
      }
      return;
    }
    final left = expires.difference(DateTime.now().toUtc());
    final next = left.isNegative ? Duration.zero : left;
    final prev = remainingListenable.value;
    if (prev == null ||
        prev.inMinutes != next.inMinutes ||
        (next == Duration.zero && prev != Duration.zero)) {
      remainingListenable.value = next;
    }
  }

  void _bumpSitesRevision() {
    _sitesRevision++;
  }

  void _unbindListeners() {
    if (_discovery != null && _discoveryListener != null) {
      _discovery!.removeListener(_discoveryListener!);
    }
    _discoveryListener = null;
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _unbindListeners();
    remainingListenable.dispose();
    super.dispose();
  }
}
