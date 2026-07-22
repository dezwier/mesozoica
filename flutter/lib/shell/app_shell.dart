import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/catalog_mode_controller.dart';
import '../controllers/field_discovery_coordinator.dart';
import '../controllers/field_session_coordinator.dart';
import '../controllers/map_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/site_catalog_controller.dart';
import '../controllers/fossil_catalog_controller.dart';
import '../controllers/splash_hold_provider.dart';
import '../controllers/walk_distance_controller.dart';
import '../models/fossil.dart';
import '../models/site.dart';
import '../models/user_notification.dart';
import '../services/api_response_cache.dart';
import '../services/location_service.dart';
import '../services/push_notification_service.dart';
import '../services/site_service.dart';
import '../widgets/cards/fossil_discovery_celebration.dart';
import '../widgets/cards/site_discovery_celebration.dart';
import '../widgets/common/app_splash_screen.dart';
import '../widgets/profile/community_drawer.dart';
import '../screens/catalog/catalog_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/tool/tool_screen.dart';
import 'map_bottom_chrome.dart';
import 'map_top_chrome.dart';
import 'shell_overlay_panel.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  bool _profileOpen = false;
  bool _catalogOpen = false;
  bool _toolsOpen = false;
  final _catalogScreenKey = GlobalKey<CatalogScreenState>();
  final _toolScreenKey = GlobalKey<ToolScreenState>();
  int? _previousUserId;
  CatalogDataSource? _previousCatalogDataSource;
  CatalogModeController? _catalogModeController;
  FieldDiscoveryCoordinator? _discoveryCoordinator;
  MapController? _mapController;
  StreamSubscription<RemoteMessage>? _foregroundPushSub;
  StreamSubscription<RemoteMessage>? _openedPushSub;
  bool _celebrationShowing = false;
  bool _appInForeground = true;

  bool get _anyOverlayOpen => _profileOpen || _catalogOpen || _toolsOpen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachCatalogModeListener();
      final discovery = context.read<FieldDiscoveryCoordinator>();
      _discoveryCoordinator = discovery;
      discovery.addListener(_onDiscoveryChanged);
      discovery.bind(locationService: context.read<LocationService>());

      final map = context.read<MapController>();
      _mapController = map;
      map.addListener(_onMapSitesChanged);
      discovery.ingestMapSites(map.geoSites);

      context.read<FieldSessionCoordinator>().bind(
            locationService: context.read<LocationService>(),
            onEnsureScheduled: () {
              context.read<MapController>().scheduleFieldPollAfterEnsure();
              unawaited(
                context
                    .read<FieldDiscoveryCoordinator>()
                    .refreshDiscoverableCache(force: true),
              );
            },
          );
      context.read<FieldSessionCoordinator>().onForeground();
      unawaited(
        context.read<WalkDistanceController>().bind(
              context.read<LocationService>(),
            ),
      );
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

    // Card map taps queue a focus request; close overlays so MapScreen can pan.
    if (map.pendingFocusSite != null && _anyOverlayOpen) {
      setState(() {
        _profileOpen = false;
        _catalogOpen = false;
        _toolsOpen = false;
      });
    }
  }

  void _onDiscoveryChanged() {
    if (!mounted) return;
    final discovery = context.read<FieldDiscoveryCoordinator>();
    final pending = discovery.pendingCelebration;
    if (pending == null) return;

    // Always refresh map/catalog/inbox; push already covers background UX.
    context.read<MapController>().load(force: true);
    context.read<SiteCatalogController>().load(force: true);
    final auth = context.read<AuthController>();
    unawaited(auth.refreshProfile());
    final userId = auth.currentUser?.id;
    if (userId != null) {
      context
          .read<NotificationController>()
          .refreshInBackground(authenticatedUserId: userId);
    }

    // Defer the in-app celebration dialog until the app is foregrounded.
    if (!_appInForeground) return;
    _showPendingCelebrationIfAny();
  }

  void _showPendingCelebrationIfAny() {
    if (!mounted) return;
    final discovery = context.read<FieldDiscoveryCoordinator>();
    final pending = discovery.pendingCelebration;
    if (pending == null) return;
    discovery.consumeCelebration();
    unawaited(_showCelebration(discover: pending));
  }

  Future<void> _showCelebration({
    FieldDiscoverResponse? discover,
    SiteSummary? site,
    int? siteId,
  }) async {
    if (!mounted || _celebrationShowing) return;
    final resolvedSite = discover?.site ?? site;
    if (resolvedSite == null && siteId == null) return;
    _celebrationShowing = true;
    try {
      await showSiteDiscoveryCelebration(
        context,
        site: resolvedSite,
        siteId: siteId,
      );
      if (!mounted) return;
      final fossils = await _resolveSurfaceFossils(discover);
      if (!mounted || fossils.isEmpty) return;
      await showFossilDiscoveryCelebrations(context, fossils: fossils);
      if (!mounted) return;
      unawaited(context.read<FossilCatalogController>().load(force: true));
    } finally {
      _celebrationShowing = false;
    }
  }

  Future<List<FossilSummary>> _resolveSurfaceFossils(
    FieldDiscoverResponse? discover,
  ) async {
    if (discover == null) return const [];
    if (discover.fossilsReady) {
      return discover.surfaceFossils;
    }
    final jobId = discover.jobId;
    if (jobId == null) return discover.surfaceFossils;
    final location = context.read<LocationService>().currentLocation;
    if (location == null) return const [];
    final service = SiteService();
    try {
      final job = await service.waitForFieldSurveyJob(jobId);
      if (!job.isDone || !mounted) return const [];
      final refreshed = await service.discoverSite(
        siteId: discover.site.siteId,
        lat: location.latitude,
        lon: location.longitude,
      );
      return refreshed.surfaceFossils;
    } catch (_) {
      return const [];
    } finally {
      service.dispose();
    }
  }

  void _setupPushHandling() {
    if (kIsWeb) return;
    try {
      unawaited(PushNotificationService.init());
      _foregroundPushSub = FirebaseMessaging.onMessage.listen((msg) {
        final type = msg.data['type']?.toString() ?? '';
        if (type != 'site_discovered' &&
            type != 'friend_request_received' &&
            type != 'friend_request_accepted') {
          return;
        }
        if (!mounted) return;
        final uid = context.read<AuthController>().currentUser?.id;
        if (uid == null) return;
        context
            .read<NotificationController>()
            .refreshInBackground(authenticatedUserId: uid);
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
    if (type != 'site_discovered') return;
    final rawSiteId = msg.data['site_id'];
    final siteId =
        rawSiteId != null ? int.tryParse(rawSiteId.toString()) : null;
    if (siteId == null) return;
    unawaited(_showCelebration(siteId: siteId));
  }

  @override
  void dispose() {
    _discoveryCoordinator?.removeListener(_onDiscoveryChanged);
    _mapController?.removeListener(_onMapSitesChanged);
    _catalogModeController?.removeListener(_onCatalogModeChanged);
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
        fieldSession.onForeground();
        unawaited(
          context
              .read<FieldDiscoveryCoordinator>()
              .refreshDiscoverableCache(force: true),
        );
        final auth = context.read<AuthController>();
        final userId = auth.currentUser?.id;
        if (userId != null) {
          context
              .read<NotificationController>()
              .refreshInBackground(authenticatedUserId: userId);
        }
        unawaited(
          context.read<WalkDistanceController>().onAppResumed(
                profile: auth.currentUser,
              ),
        );
        _showPendingCelebrationIfAny();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appInForeground = false;
        fieldSession.onBackground();
        unawaited(context.read<WalkDistanceController>().onAppBackgrounded());
      case AppLifecycleState.detached:
        _appInForeground = false;
        fieldSession.onLifecycle(state);
        unawaited(context.read<WalkDistanceController>().onAppBackgrounded());
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
    context.read<MapController>().onUserChanged(isAdmin: isAdmin);
    context.read<FieldDiscoveryCoordinator>().clearForUserChange();
    context.read<SiteCatalogController>().load(force: true);

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
      await PushNotificationService.registerTokenIfLoggedIn();
      if (!mounted || _previousUserId != userId) return;
      unawaited(
        context
            .read<FieldDiscoveryCoordinator>()
            .refreshDiscoverableCache(force: true),
      );
    });
  }

  void _openProfile() {
    setState(() {
      _catalogOpen = false;
      _toolsOpen = false;
      _profileOpen = true;
    });
  }

  void _openCatalog() {
    if (_catalogOpen) {
      _catalogScreenKey.currentState?.scrollActiveTabToTop();
      return;
    }
    setState(() {
      _profileOpen = false;
      _toolsOpen = false;
      _catalogOpen = true;
    });
  }

  void _openTools() {
    if (_toolsOpen) {
      _toolScreenKey.currentState?.scrollToTop();
      return;
    }
    setState(() {
      _profileOpen = false;
      _catalogOpen = false;
      _toolsOpen = true;
    });
  }

  void _closeOverlays() {
    if (!_anyOverlayOpen) return;
    setState(() {
      _profileOpen = false;
      _catalogOpen = false;
      _toolsOpen = false;
    });
  }

  void _onNotificationTap(UserNotificationItem item) {
    if (item.isSiteDiscovered) {
      final siteId = item.siteId;
      if (siteId == null) return;
      unawaited(_showCelebration(siteId: siteId));
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
    return Consumer2<AuthController, SplashHoldProvider>(
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
                  MapScreen(isActive: !_anyOverlayOpen),
                  Offstage(
                    offstage: !_catalogOpen,
                    child: TickerMode(
                      enabled: _catalogOpen,
                      child: ShellOverlayPanel(
                        onClose: _closeOverlays,
                        child: CatalogScreen(
                          key: _catalogScreenKey,
                          isActive: _catalogOpen,
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
                        onClose: _closeOverlays,
                        child: ToolScreen(
                          key: _toolScreenKey,
                          isActive: _toolsOpen,
                        ),
                      ),
                    ),
                  ),
                  if (!_anyOverlayOpen) ...[
                    MapTopChrome(
                      showNotifications: auth.isLoggedIn,
                      onTapNotification: _onNotificationTap,
                    ),
                    MapBottomChrome(
                      onOpenProfile: _openProfile,
                      onOpenCatalog: _openCatalog,
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
