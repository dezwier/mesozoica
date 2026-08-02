import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/game_config.dart';
import '../controllers/field_discovery_coordinator.dart';
import '../models/site.dart';
import '../models/terrain_echo_kind.dart';
import '../models/tool.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';
import '../services/tool_service.dart';

/// Active timed Terrain Echo session (vintage radar overlay).
class TerrainEchoController extends ChangeNotifier {
  TerrainEchoController({
    ToolService? toolService,
    SiteService? siteService,
  })  : _toolService = toolService ?? ToolService(),
        _siteService = siteService ?? SiteService();

  final ToolService _toolService;
  final SiteService _siteService;

  FieldDiscoveryCoordinator? _discovery;
  LocationService? _location;
  VoidCallback? _discoveryListener;
  VoidCallback? _locationListener;

  TerrainEchoSession? _session;
  ToolSummary? _tool;
  bool _activating = false;
  String? _message;
  bool _requestShowOnMap = false;
  Timer? _tickTimer;
  LatLng? _lastOrigin;
  int _sitesRevision = 0;

  /// Countdown for HUD / tool cards — does not trigger [notifyListeners].
  final ValueNotifier<Duration?> remainingListenable =
      ValueNotifier<Duration?>(null);

  bool get isActive =>
      _session != null && _session!.isActive && !_session!.isExpired;
  TerrainEchoSession? get session => _session;
  ToolSummary? get tool => _tool;
  bool get isActivating => _activating;
  String? get message => _message;
  bool get requestShowOnMap => _requestShowOnMap;

  /// Bumps when discoverable sites or GPS origin for the overlay change.
  int get sitesRevision => _sitesRevision;

  Duration? get remaining => remainingListenable.value;

  double get accuracy {
    final session = _session;
    if (session != null) return session.accuracy;
    return GameConfig.instance.toolActions.terrainEcho.accuracy;
  }

  double get rangeM {
    final session = _session;
    if (session != null) return session.rangeM;
    return GameConfig.instance.toolActions.terrainEcho.rangeM;
  }

  double get ringIncrementM =>
      GameConfig.instance.toolActions.terrainEcho.ringIncrementM;

  double get sweepPeriodS =>
      GameConfig.instance.toolActions.terrainEcho.sweepPeriodS;

  LatLng? get origin => _location?.currentLocation;

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
    _locationListener = _onLocationChanged;
    discovery.addListener(_discoveryListener!);
    location.addListener(_locationListener!);
    unawaited(restoreActiveSession());
  }

  Future<void> restoreActiveSession() async {
    if (_activating) return;
    try {
      final session = await _toolService.fetchActiveTerrainEchoSession();
      if (session == null || !session.isActive || session.isExpired) {
        if (_session != null && !isActive) {
          await stop(notifyServer: false);
        }
        return;
      }
      if (_session?.sessionId == session.sessionId && isActive) {
        _session = session;
        _ensureTickTimer();
        await _syncDiscoveryRadius(forceRefresh: false);
        return;
      }
      _session = session;
      _tool = null;
      _ensureTickTimer();
      await _syncDiscoveryRadius(forceRefresh: true);
      _message = '${TerrainEchoKind.toolName} active';
      _bumpSitesRevision();
      notifyListeners();
    } catch (error) {
      debugPrint('Terrain echo restore failed: $error');
    }
  }

  void consumeShowOnMapRequest() {
    _requestShowOnMap = false;
  }

  Future<void> activate(ToolSummary tool) async {
    if (!tool.isOwned) return;
    if (!TerrainEchoKind.matchesToolName(tool.name)) return;

    _activating = true;
    _message = null;
    notifyListeners();
    try {
      final session =
          await _toolService.startTerrainEchoSession(toolId: tool.id);
      _session = session;
      _tool = tool;
      _requestShowOnMap = true;
      _ensureTickTimer();
      await _syncDiscoveryRadius(forceRefresh: true);
      unawaited(_ensureFieldSites());
      _message = '${TerrainEchoKind.toolName} active';
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
        await _toolService.cancelTerrainEchoSession();
      } catch (_) {
        // Local stop still clears overlays.
      }
    }
    _session = null;
    _tool = null;
    _lastOrigin = null;
    _discovery?.setCacheRadiusOverrideKm(null);
    _message = null;
    remainingListenable.value = null;
    _bumpSitesRevision();
    if (hadSession) notifyListeners();
  }

  /// Clear local UI when another tool session took over on the server.
  void clearLocalSession() {
    if (_session == null) return;
    unawaited(stop(notifyServer: false));
  }

  void _onDiscoveryChanged() {
    if (!isActive) return;
    _bumpSitesRevision();
    notifyListeners();
  }

  void _onLocationChanged() {
    if (!isActive) return;
    final loc = _location?.currentLocation;
    if (loc == null) return;
    final prev = _lastOrigin;
    if (prev == null ||
        Geolocator.distanceBetween(
              prev.latitude,
              prev.longitude,
              loc.latitude,
              loc.longitude,
            ) >=
            5) {
      _lastOrigin = loc;
      _bumpSitesRevision();
      notifyListeners();
    }
    final rem = remaining;
    if (rem != null && rem <= Duration.zero) {
      unawaited(stop(notifyServer: false));
    }
  }

  Future<void> _syncDiscoveryRadius({required bool forceRefresh}) async {
    final discovery = _discovery;
    if (discovery == null || !isActive) return;
    discovery.setCacheRadiusOverrideKm(rangeM / 1000.0);
    if (forceRefresh) {
      await discovery.refreshDiscoverableCache(force: true);
    }
  }

  Future<void> _ensureFieldSites() async {
    final loc = _location?.currentLocation;
    if (loc == null) return;
    final radiusKm =
        GameConfig.instance.siteGeneration.client.nearbyRadiusKm;
    try {
      await _siteService.requestFieldSiteEnsure(
        lat: loc.latitude,
        lon: loc.longitude,
        radiusKm: radiusKm,
        reason: 'terrain_echo',
      );
      await _discovery?.refreshDiscoverableCache(force: true);
      _bumpSitesRevision();
      notifyListeners();
    } catch (error) {
      debugPrint('Terrain echo ensure failed: $error');
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
    if (_location != null && _locationListener != null) {
      _location!.removeListener(_locationListener!);
    }
    _discoveryListener = null;
    _locationListener = null;
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _unbindListeners();
    remainingListenable.dispose();
    super.dispose();
  }
}
