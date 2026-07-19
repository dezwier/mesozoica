import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/catalog_mode_controller.dart';
import '../controllers/field_discovery_coordinator.dart';
import '../controllers/field_session_coordinator.dart';
import '../controllers/map_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/site_catalog_controller.dart';
import '../controllers/fossil_catalog_controller.dart';
import '../models/site.dart';
import '../models/user_notification.dart';
import '../services/api_response_cache.dart';
import '../services/location_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/cards/site_discovery_celebration.dart';
import '../widgets/common/gradient_app_bar.dart';
import '../widgets/common/catalog_mode_toggle.dart';
import '../widgets/common/notification_icon_button.dart';
import '../widgets/profile/community_drawer.dart';
import '../screens/catalog/catalog_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/profile/profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _mapTabIndex = 0;
  static const _catalogTabIndex = 1;

  int _index = _catalogTabIndex;
  final _catalogScreenKey = GlobalKey<CatalogScreenState>();
  int? _previousUserId;
  CatalogDataSource? _previousCatalogDataSource;
  CatalogModeController? _catalogModeController;
  FieldDiscoveryCoordinator? _discoveryCoordinator;
  MapController? _mapController;
  StreamSubscription<RemoteMessage>? _foregroundPushSub;
  StreamSubscription<RemoteMessage>? _openedPushSub;
  bool _celebrationShowing = false;

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
    final discovery = _discoveryCoordinator;
    if (map == null || discovery == null) return;
    discovery.ingestMapSites(map.geoSites);
  }

  void _onDiscoveryChanged() {
    if (!mounted) return;
    final discovery = context.read<FieldDiscoveryCoordinator>();
    final pending = discovery.pendingCelebration;
    if (pending == null) return;
    discovery.consumeCelebration();
    context.read<MapController>().load(force: true);
    context.read<SiteCatalogController>().load(force: true);
    final userId = context.read<AuthController>().currentUser?.id;
    if (userId != null) {
      context
          .read<NotificationController>()
          .refreshInBackground(authenticatedUserId: userId);
    }
    unawaited(_showCelebration(site: pending));
  }

  Future<void> _showCelebration({
    SiteSummary? site,
    int? siteId,
  }) async {
    if (!mounted || _celebrationShowing) return;
    if (site == null && siteId == null) return;
    _celebrationShowing = true;
    try {
      await showSiteDiscoveryCelebration(
        context,
        site: site,
        siteId: siteId,
      );
    } finally {
      _celebrationShowing = false;
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
        fieldSession.onForeground();
        unawaited(
          context
              .read<FieldDiscoveryCoordinator>()
              .refreshDiscoverableCache(force: true),
        );
        final userId = context.read<AuthController>().currentUser?.id;
        if (userId != null) {
          context
              .read<NotificationController>()
              .refreshInBackground(authenticatedUserId: userId);
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        fieldSession.onBackground();
      case AppLifecycleState.detached:
        fieldSession.onLifecycle(state);
    }
  }

  void _syncNotificationStore(AuthController auth) {
    final userId = auth.currentUser?.id;
    if (userId == _previousUserId) return;

    final notificationController = context.read<NotificationController>();
    final previousUserId = _previousUserId;
    _previousUserId = userId;

    if (previousUserId != null && userId == null) {
      notificationController.clear();
      ApiResponseCache.instance.clearForUser(previousUserId);
      return;
    }
    if (userId == null) return;

    Future.microtask(() async {
      if (!mounted || _previousUserId != userId) return;
      await notificationController.hydrate(userId);
      if (!mounted || _previousUserId != userId) return;
      await notificationController.refreshInBackground(
        authenticatedUserId: userId,
      );
      await PushNotificationService.registerTokenIfLoggedIn();
    });
  }

  void _onDestinationSelected(int index) {
    if (index == _index && index == _catalogTabIndex) {
      _catalogScreenKey.currentState?.scrollActiveTabToTop();
      return;
    }
    setState(() => _index = index);
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
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncNotificationStore(auth);
        });

        return Scaffold(
          appBar: GradientAppBar(
            title: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Image.asset('assets/images/logo.png', height: 32),
            ),
            center: const CatalogModeToggle(),
            actions: auth.isLoggedIn
                ? [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: NotificationIconButton(
                        onTapNotification: _onNotificationTap,
                      ),
                    ),
                  ]
                : null,
          ),
          body: IndexedStack(
            index: _index,
            children: [
              MapScreen(isActive: _index == _mapTabIndex),
              CatalogScreen(
                key: _catalogScreenKey,
                isActive: _index == _catalogTabIndex,
              ),
              ProfileScreen(isActive: _index == 2),
            ],
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _onDestinationSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Map',
                ),
                NavigationDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  selectedIcon: Icon(Icons.collections_bookmark),
                  label: 'Catalog',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outlined),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
