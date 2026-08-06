import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/game_config.dart';
import '../config/main_param_resolve.dart';
import '../config/tool_instance_params.dart';
import '../controllers/aerial_session_controller.dart';
import '../controllers/auth_controller.dart';
import '../controllers/catalog_mode_controller.dart';
import '../controllers/disguise_session_controller.dart';
import '../controllers/field_discovery_coordinator.dart';
import '../controllers/field_session_coordinator.dart';
import '../controllers/formation_map_controller.dart';
import '../controllers/main_param_buff_controller.dart';
import '../controllers/orbit_survey_controller.dart';
import '../controllers/terrain_echo_controller.dart';
import '../controllers/guidance_session_controller.dart';
import '../controllers/map_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/site_catalog_controller.dart';
import '../controllers/fossil_catalog_controller.dart';
import '../controllers/splash_hold_controller.dart';
import '../controllers/tool_catalog_controller.dart';
import '../controllers/walk_distance_controller.dart';
import '../controllers/weather_controller.dart';
import '../controllers/site_exploration_controller.dart';
import '../controllers/xp_award_controller.dart';
import '../models/fossil.dart';
import '../models/site.dart';
import '../models/user_notification.dart';
import '../services/api_response_cache.dart';
import '../services/location_service.dart';
import '../services/push_notification_service.dart';
import '../services/site_service.dart';
import '../widgets/cards/card_detail_sheet.dart';
import '../widgets/cards/site_discovery_celebration.dart';
import '../widgets/common/app_splash_screen.dart';
import '../widgets/profile/community_drawer.dart';
import '../widgets/weather/weather_detail_sheet.dart';
import '../screens/dino/dino_screen.dart';
import '../screens/fossil/fossil_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/site/site_screen.dart';
import '../screens/tool/tool_screen.dart';
import 'map_bottom_chrome.dart';
import 'map_top_chrome.dart';
import 'shell_overlay_panel.dart';

part 'app_shell_discovery.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, _AppShellDiscoveryMixin {
  bool _profileOpen = false;
  bool _sitesOpen = false;
  bool _fossilsOpen = false;
  bool _dinosaursOpen = false;
  bool _toolsOpen = false;
  final _siteScreenKey = GlobalKey<SiteScreenState>();
  final _fossilScreenKey = GlobalKey<FossilScreenState>();
  final _dinoScreenKey = GlobalKey<DinoScreenState>();
  final _toolScreenKey = GlobalKey<ToolScreenState>();
  int? _previousUserId;
  CatalogDataSource? _previousCatalogDataSource;
  CatalogModeController? _catalogModeController;
  FieldDiscoveryCoordinator? _discoveryCoordinator;
  SiteExplorationController? _explorationController;
  MapController? _mapController;
  AerialSessionController? _aerialRecon;
  GuidanceSessionController? _guidance;
  OrbitSurveyController? _orbitSurvey;
  FormationMapController? _formationMap;
  TerrainEchoController? _terrainEcho;
  MainParamBuffController? _mainParamBuff;
  DisguiseSessionController? _disguise;
  WeatherController? _weather;
  StreamSubscription<RemoteMessage>? _foregroundPushSub;
  StreamSubscription<RemoteMessage>? _openedPushSub;

  /// Cached so aerial session list refreshes do not rebuild the shell.
  bool _aerialDrawMode = false;

  bool get _anyCatalogOpen => _sitesOpen || _fossilsOpen || _dinosaursOpen;
  bool get _weatherOpen => WeatherDetailSheet.isOpen;
  bool get _anyOverlayOpen =>
      _profileOpen || _anyCatalogOpen || _toolsOpen || _weatherOpen;
  bool get _cardDetailOpen => CardDetailSheet.isOpen;

  /// Bottom / top chrome hide while any overlay / card dialog is open (or aerial draw).
  bool get _hideChrome => _anyOverlayOpen || _aerialDrawMode || _cardDetailOpen;

  void _clearOverlayFlags() {
    _profileOpen = false;
    _sitesOpen = false;
    _fossilsOpen = false;
    _dinosaursOpen = false;
    _toolsOpen = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CardDetailSheet.openCount.addListener(_onCardDetailOverlayChanged);
    WeatherDetailSheet.openCount.addListener(_onWeatherOverlayChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthController>().bindXpAwards(
        context.read<XpAwardController>(),
      );
      _attachCatalogModeListener();
      final discovery = context.read<FieldDiscoveryCoordinator>();
      _discoveryCoordinator = discovery;
      discovery.addListener(_onDiscoveryChanged);
      discovery.bind(locationService: context.read<LocationService>());

      final map = context.read<MapController>();
      _mapController = map;
      map.addListener(_onMapSitesChanged);
      discovery.ingestMapSites(map.geoSites);

      final aerial = context.read<AerialSessionController>();
      _aerialRecon = aerial;
      _aerialDrawMode = aerial.isDrawMode;
      aerial.addListener(_onAerialReconChanged);

      final guidance = context.read<GuidanceSessionController>();
      _guidance = guidance;
      guidance.addListener(_onGuidanceChanged);
      guidance.bind(
        discovery: discovery,
        location: context.read<LocationService>(),
      );

      final orbit = context.read<OrbitSurveyController>();
      _orbitSurvey = orbit;
      orbit.addListener(_onOrbitSurveyChanged);
      orbit.bind(
        discovery: discovery,
        location: context.read<LocationService>(),
      );

      final formationMap = context.read<FormationMapController>();
      _formationMap = formationMap;
      formationMap.addListener(_onFormationMapChanged);
      formationMap.bind(
        discovery: discovery,
        location: context.read<LocationService>(),
      );

      final terrainEcho = context.read<TerrainEchoController>();
      _terrainEcho = terrainEcho;
      terrainEcho.addListener(_onTerrainEchoChanged);
      terrainEcho.bind(
        discovery: discovery,
        location: context.read<LocationService>(),
      );

      final mainParamBuff = context.read<MainParamBuffController>();
      _mainParamBuff = mainParamBuff;
      mainParamBuff.addListener(_onMainParamBuffChanged);

      final disguise = context.read<DisguiseSessionController>();
      _disguise = disguise;
      disguise.addListener(_onDisguiseChanged);

      final weather = context.read<WeatherController>();
      _weather = weather;
      weather.addListener(_onWeatherChanged);

      unawaited(() async {
        await mainParamBuff.restoreActiveSession();
        await disguise.restoreActiveSession();
        if (mounted) {
          await mainParamBuff.stopIfPeriodLeft(weather.weatherTime);
          _syncMainParamBuffEffects();
        }
      }());

      // bind → _startSession → onForeground (startup ensure). Do not call
      // onForeground again here — a second epoch aborts the first resume
      // mid-GPS and can leave ensure never POSTed until a cell move.
      context.read<FieldSessionCoordinator>().bind(
        locationService: context.read<LocationService>(),
        onEnsureScheduled: () {
          context.read<MapController>().scheduleFieldPollAfterEnsure();
          unawaited(
            context.read<FieldDiscoveryCoordinator>().refreshDiscoverableCache(
              force: true,
            ),
          );
        },
      );
      unawaited(
        context
            .read<WalkDistanceController>()
            .bind(
              context.read<LocationService>(),
              onProfileUpdated: (profile) async {
                final walk = context.read<WalkDistanceController>();
                final gap = walk.takePendingVisitGapMeters();
                await context.read<AuthController>().applyUser(
                  profile,
                  exploredSinceLastVisitM: gap,
                );
              },
            )
            .then((_) async {
              if (!mounted) return;
              // Cold start never gets a resumed lifecycle transition — reconcile
              // Health passive distance and surface the visit XP badge.
              await context.read<WalkDistanceController>().onAppResumed(
                profile: context.read<AuthController>().currentUser,
              );
            }),
      );
      unawaited(
        context.read<SiteExplorationController>().bind(
          context.read<LocationService>(),
          discoveredSitesProvider: () {
            final map = context.read<MapController>();
            return map.geoSites
                .where(
                  (s) =>
                      s.discoveredAt != null ||
                      (s.status != null && s.status != 'hidden'),
                )
                .toList();
          },
          skillLevelProvider: () {
            final profile = context.read<AuthController>().currentUser;
            if (profile != null) {
              for (final skill in profile.skills) {
                if (skill.id == 'field_survey') {
                  return skill.level.clamp(1, 99);
                }
              }
            }
            return 1;
          },
          onProfileUpdated: (profile) async {
            await context.read<AuthController>().applyUser(profile);
          },
          onSiteUpdated: (site) {
            context.read<MapController>().upsertSite(site);
            context.read<SiteCatalogController>().upsertSite(site);
          },
        ),
      );
      final exploration = context.read<SiteExplorationController>();
      _explorationController = exploration;
      exploration.addListener(_onExplorationChanged);
      _setupPushHandling();
    });
  }

  void _attachCatalogModeListener() {
    final controller = context.read<CatalogModeController>();
    _catalogModeController = controller;
    controller.addListener(_onCatalogModeChanged);
    _previousCatalogDataSource = controller.dataSource;
  }

  void _onCatalogModeChanged() {
    if (!mounted) return;
    final source = context.read<CatalogModeController>().dataSource;
    if (source == _previousCatalogDataSource) return;
    _previousCatalogDataSource = source;

    context.read<MapController>().onDataSourceChanged();
    context.read<SiteCatalogController>().load(force: true);
    context.read<FossilCatalogController>().load(force: true);
  }

  void _onMapSitesChanged() {
    if (!mounted) return;
    final map = _mapController;
    if (map == null) return;
    _discoveryCoordinator?.ingestMapSites(map.geoSites);
    context.read<SiteExplorationController>().ingestSites(map.geoSites);

    // Card map taps queue a focus request; close overlays so MapScreen can pan.
    if (map.pendingFocusSite != null && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
    }
  }

  void _onGuidanceChanged() {
    if (!mounted) return;
    final guidance = _guidance;
    if (guidance == null) return;
    // Activate requests the map; close tool/profile overlays so the map
    // is visible (mirrors aerial draw-mode behavior).
    if (guidance.requestShowOnMap && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
    }
    // Do not setState on every guidance notify — map/HUD listen locally.
  }

  void _onOrbitSurveyChanged() {
    if (!mounted) return;
    final orbit = _orbitSurvey;
    if (orbit == null) return;
    if (orbit.requestShowOnMap && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
    }
  }

  void _onFormationMapChanged() {
    if (!mounted) return;
    final formation = _formationMap;
    if (formation == null) return;
    if (formation.requestShowOnMap && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
    }
  }

  void _onTerrainEchoChanged() {
    if (!mounted) return;
    final echo = _terrainEcho;
    if (echo == null) return;
    if (echo.requestShowOnMap && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
    }
  }

  void _onMainParamBuffChanged() {
    if (!mounted) return;
    final buff = _mainParamBuff;
    if (buff == null) return;
    if (buff.requestShowOnMap && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
    }
    _syncMainParamBuffEffects();
  }

  void _onWeatherChanged() {
    if (!mounted) return;
    final buff = _mainParamBuff;
    final weather = _weather;
    if (buff != null && weather != null) {
      unawaited(buff.stopIfPeriodLeft(weather.weatherTime));
    }
    _syncMainParamBuffEffects();
  }

  void _onDisguiseChanged() {
    if (!mounted) return;
    final disguise = _disguise;
    if (disguise == null) return;
    if ((disguise.requestShowOnMap || disguise.isPickMode) && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
    }
  }

  /// Apply active tool buffs to speed gates + site exploration radius.
  void _syncMainParamBuffEffects() {
    if (!mounted) return;
    final walk = context.read<WalkDistanceController>();
    final exploration = context.read<SiteExplorationController>();
    final discovery = context.read<FieldDiscoveryCoordinator>();
    final base = (() {
      try {
        return GameConfig.instance.siteDiscovery.discoveryMaxSpeedKmh;
      } catch (_) {
        return 10.0;
      }
    })();

    ParamModifier? speedMod;
    final buff = _mainParamBuff;
    final weatherTime = _weather?.weatherTime;
    List<ToolModBinding> siteVisBindings = const [];
    if (buff != null &&
        buff.isActive &&
        buff.isLiveForWeatherTime(weatherTime)) {
      final mods = modifiesMainParamsFromParams(buff.session?.params);
      speedMod = mods?.paramsFor(
        'using',
        'field_survey',
      )['discovery_max_speed_kmh'];
      if (mods != null) {
        siteVisBindings = [
          ToolModBinding(
            actionKey: buff.kind?.actionKey ?? buff.session?.actionKey ?? '',
            toolName: buff.tool?.name ?? buff.kind?.toolName ?? '',
            mods: mods,
            applyOwning: false,
            applyUsing: true,
            activeWeatherTimes: buff.activeWeatherTimes,
          ),
        ];
      }
    }

    final effective = resolveScalarMainParam(
      base: base,
      levelEntries: const [],
      skillLevel: 1,
      weatherTimeMods: const [],
      weatherTypeMods: const [],
      toolMod: speedMod,
    );
    walk.updateMaxDiscoverySpeedKmh(effective);
    discovery.setMaxDiscoverySpeedKmh(effective);

    exploration.updateSiteVisibilityM(
      resolveSiteStewardshipSiteVisibilityM(
        skillLevel: 1,
        weatherTime: weatherTime,
        weatherType: _weather?.status?.weatherType,
        toolBindings: siteVisBindings,
      ),
    );
    exploration.updateDiscoverySpeed(
      resolveSiteStewardshipDiscoverySpeed(
        skillLevel: 1,
        weatherTime: weatherTime,
        weatherType: _weather?.status?.weatherType,
        toolBindings: siteVisBindings,
      ),
    );
  }

  void _onCardDetailOverlayChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onWeatherOverlayChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onAerialReconChanged() {
    if (!mounted) return;
    final aerial = _aerialRecon;
    if (aerial == null) return;
    if (aerial.isDrawMode && _anyOverlayOpen) {
      setState(() {
        _clearOverlayFlags();
        _aerialDrawMode = true;
      });
      return;
    }
    // Session Info taps queue a focus request; close overlays so MapScreen can pan.
    if (aerial.pendingFocusSession != null && _anyOverlayOpen) {
      setState(_clearOverlayFlags);
      return;
    }

    // Session poll reports successful discover event site IDs. Upsert only
    // newly seen IDs into map + site catalog (no blind full reload).
    final gen = aerial.sessionsFetchGeneration;
    if (gen != _lastToolSessionsFetchGeneration) {
      _lastToolSessionsFetchGeneration = gen;
      _ingestAerialDiscoveredSites(
        aerial.sessions.expand((m) => m.discoveredSiteIds),
      );
    }

    // Only rebuild shell when draw mode toggles (chrome hide). MapScreen and
    // tool cards already watch AerialSessionController; session-list refreshes
    // must not setState or they re-trigger startTracking → fetch loops.
    final drawMode = aerial.isDrawMode;
    if (drawMode != _aerialDrawMode) {
      setState(() => _aerialDrawMode = drawMode);
    }
  }

  void _setupPushHandling() {
    if (kIsWeb) return;
    try {
      unawaited(PushNotificationService.init());
      _foregroundPushSub = FirebaseMessaging.onMessage.listen((msg) {
        final type = msg.data['type']?.toString() ?? '';
        if (type != 'site_discovered' &&
            type != 'site_documented' &&
            type != 'friend_request_received' &&
            type != 'friend_request_accepted') {
          return;
        }
        if (!mounted) return;
        if (type == 'site_discovered' || type == 'site_documented') {
          final rawSiteId = msg.data['site_id'];
          final siteId = rawSiteId != null
              ? int.tryParse(rawSiteId.toString())
              : null;
          _scheduleDiscoveryRefresh(siteId: siteId);
          if (type == 'site_documented' && siteId != null) {
            _queueDocumentationCelebrationSiteId(siteId);
          }
          return;
        }
        final uid = context.read<AuthController>().currentUser?.id;
        if (uid == null) return;
        context.read<NotificationController>().refreshInBackground(
          authenticatedUserId: uid,
        );
      });

      unawaited(
        FirebaseMessaging.instance.getInitialMessage().then((msg) {
          if (msg == null || !mounted) return;
          _handlePushOpen(msg);
        }),
      );
      _openedPushSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        if (!mounted) return;
        _handlePushOpen(msg);
      });
    } catch (_) {
      // Firebase not configured.
    }
  }

  void _handlePushOpen(RemoteMessage msg) {
    final type = msg.data['type']?.toString() ?? '';
    final rawSiteId = msg.data['site_id'];
    final siteId = rawSiteId != null
        ? int.tryParse(rawSiteId.toString())
        : null;
    if (siteId == null) return;
    if (type == 'site_discovered') {
      _scheduleDiscoveryRefresh(siteId: siteId);
      unawaited(_showCelebration(siteId: siteId));
      return;
    }
    if (type == 'site_documented') {
      _scheduleDiscoveryRefresh(siteId: siteId);
      _queueDocumentationCelebrationSiteId(siteId);
    }
  }

  @override
  void dispose() {
    CardDetailSheet.openCount.removeListener(_onCardDetailOverlayChanged);
    WeatherDetailSheet.openCount.removeListener(_onWeatherOverlayChanged);
    _discoveryCoordinator?.removeListener(_onDiscoveryChanged);
    _explorationController?.removeListener(_onExplorationChanged);
    _mapController?.removeListener(_onMapSitesChanged);
    _aerialRecon?.removeListener(_onAerialReconChanged);
    _guidance?.removeListener(_onGuidanceChanged);
    _orbitSurvey?.removeListener(_onOrbitSurveyChanged);
    _formationMap?.removeListener(_onFormationMapChanged);
    _terrainEcho?.removeListener(_onTerrainEchoChanged);
    _mainParamBuff?.removeListener(_onMainParamBuffChanged);
    _disguise?.removeListener(_onDisguiseChanged);
    _weather?.removeListener(_onWeatherChanged);
    _catalogModeController?.removeListener(_onCatalogModeChanged);
    _discoveryRefreshTimer?.cancel();
    unawaited(_foregroundPushSub?.cancel() ?? Future<void>.value());
    unawaited(_openedPushSub?.cancel() ?? Future<void>.value());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    final fieldSession = context.read<FieldSessionCoordinator>();
    switch (state) {
      case AppLifecycleState.resumed:
        _appInForeground = true;
        // Flush any badge XP held while away before resume syncs announce more.
        context.read<XpAwardController>().setAppForeground(true);
        fieldSession.onForeground();
        unawaited(
          context.read<FieldDiscoveryCoordinator>().refreshDiscoverableCache(
            force: true,
          ),
        );
        unawaited(
          context.read<GuidanceSessionController>().restoreActiveSession(),
        );
        unawaited(context.read<OrbitSurveyController>().restoreActiveSession());
        unawaited(
          context.read<FormationMapController>().restoreActiveSession(),
        );
        unawaited(context.read<TerrainEchoController>().restoreActiveSession());
        unawaited(
          context.read<MainParamBuffController>().restoreActiveSession().then((
            _,
          ) {
            if (!mounted) return;
            final weather = context.read<WeatherController>();
            unawaited(
              context.read<MainParamBuffController>().stopIfPeriodLeft(
                weather.weatherTime,
              ),
            );
          }),
        );
        unawaited(
          context.read<DisguiseSessionController>().restoreActiveSession(),
        );
        final auth = context.read<AuthController>();
        final userId = auth.currentUser?.id;
        if (userId != null) {
          context.read<NotificationController>().refreshInBackground(
            authenticatedUserId: userId,
          );
        }
        unawaited(
          context.read<WalkDistanceController>().onAppResumed(
            profile: auth.currentUser,
          ),
        );
        context.read<SiteExplorationController>().onAppResumed();
        _showPendingCelebrationIfAny();
      case AppLifecycleState.inactive:
        // Transient (Control Center, call banner, switcher). Keep GPS running
        // so move-ensure and discovery stay alive; pausing here races resume
        // and can leave location stuck off.
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appInForeground = false;
        // Hold all floating-badge XP until resume (one merged badge per source).
        context.read<XpAwardController>().setAppForeground(false);
        fieldSession.onBackground();
        unawaited(context.read<WalkDistanceController>().onAppBackgrounded());
        unawaited(
          context.read<SiteExplorationController>().onAppBackgrounded(),
        );
      case AppLifecycleState.detached:
        _appInForeground = false;
        context.read<XpAwardController>().setAppForeground(false);
        fieldSession.onLifecycle(state);
        unawaited(context.read<WalkDistanceController>().onAppBackgrounded());
        unawaited(
          context.read<SiteExplorationController>().onAppBackgrounded(),
        );
    }
  }

  void _syncNotificationStore(AuthController auth) {
    final userId = auth.currentUser?.id;
    if (userId == _previousUserId) return;

    final notificationController = context.read<NotificationController>();
    final previousUserId = _previousUserId;
    _previousUserId = userId;

    if (previousUserId != null) {
      ApiResponseCache.instance.clearForUser(previousUserId);
    }

    // Field map/catalog are per-user (user_site links). Always drop the
    // previous account's markers/list when the signed-in identity changes.
    final isAdmin = auth.currentUser?.isAdmin ?? false;
    _knownAerialDiscoveredSiteIds.clear();
    context.read<MapController>().onUserChanged(isAdmin: isAdmin);
    context.read<ToolCatalogController>().onUserChanged(isAdmin: isAdmin);
    context.read<FieldDiscoveryCoordinator>().clearForUserChange();
    unawaited(
      context.read<GuidanceSessionController>().stop(notifyServer: false),
    );
    unawaited(context.read<OrbitSurveyController>().stop(notifyServer: false));
    unawaited(context.read<FormationMapController>().stop(notifyServer: false));
    unawaited(context.read<TerrainEchoController>().stop(notifyServer: false));
    unawaited(
      context.read<MainParamBuffController>().stop(notifyServer: false),
    );
    unawaited(
      context.read<DisguiseSessionController>().stop(notifyServer: false),
    );
    context.read<SiteCatalogController>().load(force: true);
    context.read<ToolCatalogController>().load(force: true);

    if (userId == null) {
      notificationController.clear();
      return;
    }

    Future.microtask(() async {
      if (!mounted || _previousUserId != userId) return;
      await notificationController.hydrate(userId);
      if (!mounted || _previousUserId != userId) return;
      await notificationController.refreshInBackground(
        authenticatedUserId: userId,
      );
      if (!mounted || _previousUserId != userId) return;
      await PushNotificationService.registerTokenIfLoggedIn();
      if (!mounted || _previousUserId != userId) return;
      unawaited(
        context.read<FieldDiscoveryCoordinator>().refreshDiscoverableCache(
          force: true,
        ),
      );
      if (!mounted || _previousUserId != userId) return;
      await context.read<GuidanceSessionController>().restoreActiveSession();
      if (!mounted || _previousUserId != userId) return;
      await context.read<OrbitSurveyController>().restoreActiveSession();
      if (!mounted || _previousUserId != userId) return;
      await context.read<FormationMapController>().restoreActiveSession();
      if (!mounted || _previousUserId != userId) return;
      await context.read<TerrainEchoController>().restoreActiveSession();
      if (!mounted || _previousUserId != userId) return;
      await context.read<MainParamBuffController>().restoreActiveSession();
      if (!mounted || _previousUserId != userId) return;
      await context.read<MainParamBuffController>().stopIfPeriodLeft(
        context.read<WeatherController>().weatherTime,
      );
      if (!mounted || _previousUserId != userId) return;
      await context.read<DisguiseSessionController>().restoreActiveSession();
      if (!mounted || _previousUserId != userId) return;
      _syncMainParamBuffEffects();
    });
  }

  void _openProfile() {
    setState(() {
      _clearOverlayFlags();
      _profileOpen = true;
    });
  }

  void _openSites() {
    if (_sitesOpen) {
      _siteScreenKey.currentState?.scrollToTop();
      return;
    }
    setState(() {
      _clearOverlayFlags();
      _sitesOpen = true;
    });
  }

  void _openFossils() {
    if (_fossilsOpen) {
      _fossilScreenKey.currentState?.scrollToTop();
      return;
    }
    setState(() {
      _clearOverlayFlags();
      _fossilsOpen = true;
    });
  }

  void _openDinosaurs() {
    if (_dinosaursOpen) {
      _dinoScreenKey.currentState?.scrollToTop();
      return;
    }
    setState(() {
      _clearOverlayFlags();
      _dinosaursOpen = true;
    });
  }

  void _openTools() {
    if (_toolsOpen) {
      _toolScreenKey.currentState?.scrollToTop();
      return;
    }
    setState(() {
      _clearOverlayFlags();
      _toolsOpen = true;
    });
  }

  void _closeOverlays() {
    if (!_anyOverlayOpen) return;
    setState(_clearOverlayFlags);
  }

  void _onNotificationTap(UserNotificationItem item) {
    if (item.isSiteDiscovered) {
      final siteId = item.siteId;
      if (siteId == null) return;
      _scheduleDiscoveryRefresh(siteId: siteId);
      unawaited(_showCelebration(siteId: siteId));
      return;
    }
    if (item.isSiteDocumented) {
      final siteId = item.siteId;
      if (siteId == null) return;
      _scheduleDiscoveryRefresh(siteId: siteId);
      unawaited(_showDocumentationCelebration(siteId: siteId));
      return;
    }
    final actorUserId = item.actorUserId;
    if (actorUserId == null) return;
    showUserProfileSheet(
      context,
      actorUserId,
      showFriendRequestActions: item.isFriendRequestReceived,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hudVisible = !_hideChrome;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<XpAwardController>().setHudVisible(hudVisible);
    });

    return Consumer2<AuthController, SplashHoldController>(
      builder: (context, auth, splashHold, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncNotificationStore(auth);
        });

        return PopScope(
          canPop: !_anyOverlayOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _closeOverlays();
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: _anyOverlayOpen
                ? (Theme.of(context).brightness == Brightness.dark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark)
                : SystemUiOverlayStyle.light,
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  MapScreen(
                    isActive: !_anyOverlayOpen && !_cardDetailOpen,
                    // Site cards freeze map chrome/Mapbox, but keep high GPS so
                    // documentation progress on the card back stays live.
                    highPrecisionGps: !_anyOverlayOpen,
                    showControls:
                        !_anyCatalogOpen && !_toolsOpen && !_cardDetailOpen,
                  ),
                  Offstage(
                    offstage: !_sitesOpen,
                    child: TickerMode(
                      enabled: _sitesOpen,
                      child: ShellOverlayPanel(
                        opaque: false,
                        showDismiss: false,
                        onClose: _closeOverlays,
                        child: SiteScreen(
                          key: _siteScreenKey,
                          isActive: _sitesOpen,
                        ),
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: !_fossilsOpen,
                    child: TickerMode(
                      enabled: _fossilsOpen,
                      child: ShellOverlayPanel(
                        opaque: false,
                        showDismiss: false,
                        onClose: _closeOverlays,
                        child: FossilScreen(
                          key: _fossilScreenKey,
                          isActive: _fossilsOpen,
                        ),
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: !_dinosaursOpen,
                    child: TickerMode(
                      enabled: _dinosaursOpen,
                      child: ShellOverlayPanel(
                        opaque: false,
                        showDismiss: false,
                        onClose: _closeOverlays,
                        child: DinoScreen(
                          key: _dinoScreenKey,
                          isActive: _dinosaursOpen,
                        ),
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: !_profileOpen,
                    child: TickerMode(
                      enabled: _profileOpen,
                      child: ShellOverlayPanel(
                        onClose: _closeOverlays,
                        child: ProfileScreen(isActive: _profileOpen),
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: !_toolsOpen,
                    child: TickerMode(
                      enabled: _toolsOpen,
                      child: ShellOverlayPanel(
                        opaque: false,
                        showDismiss: false,
                        onClose: _closeOverlays,
                        child: ToolScreen(
                          key: _toolScreenKey,
                          isActive: _toolsOpen,
                        ),
                      ),
                    ),
                  ),
                  if (!_hideChrome) ...[
                    MapTopChrome(
                      showNotifications: auth.isLoggedIn,
                      onTapNotification: _onNotificationTap,
                      onOpenProfile: _openProfile,
                    ),
                    MapBottomChrome(
                      onOpenSites: _openSites,
                      onOpenFossils: _openFossils,
                      onOpenDinosaurs: _openDinosaurs,
                      onOpenTools: _openTools,
                    ),
                  ],
                  if (!splashHold.isInitialPageReady)
                    const Positioned.fill(child: AppSplashScreen()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
