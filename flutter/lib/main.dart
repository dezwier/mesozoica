import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/game_config.dart';
import 'config/map_config.dart';
import 'controllers/auth_controller.dart';
import 'controllers/catalog_mode_controller.dart';
import 'controllers/dinosaur_catalog_controller.dart';
import 'controllers/field_discovery_coordinator.dart';
import 'controllers/fossil_catalog_controller.dart';
import 'controllers/field_session_coordinator.dart';
import 'controllers/map_controller.dart';
import 'controllers/phylo_tree_controller.dart';
import 'controllers/site_catalog_controller.dart';
import 'controllers/tool_catalog_controller.dart';
import 'controllers/notification_controller.dart';
import 'controllers/splash_hold_provider.dart';
import 'controllers/theme_controller.dart';
import 'firebase_options.dart';
import 'services/location_service.dart';
import 'services/map_tile_cache.dart';
import 'services/push_notification_runtime.dart';
import 'shell/app_shell.dart';
import 'theme/mesozoica_theme.dart';
import 'widgets/common/app_splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Decode the same placeholder the native launch screen shows, so the first
  // Flutter frame matches with no visible change.
  await AppSplashScreen.prepare();
  await GameConfig.load();
  await _configureMapboxAccessToken();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushNotificationRuntime.init();
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Firebase init skipped/failed: $error');
    }
  }
  final themeController = ThemeController();
  await themeController.initialize();
  final catalogModeController = CatalogModeController();
  await catalogModeController.initialize();
  await MapTileCache.initialize();
  runApp(MesozoicaApp(
    themeController: themeController,
    catalogModeController: catalogModeController,
  ));
}

/// [MapboxOptions.setAccessToken] is fire-and-forget async. Wait until the
/// native side actually has the token before any MapWidget is created.
Future<void> _configureMapboxAccessToken() async {
  if (!MapConfig.hasMapboxAccessToken) {
    if (kDebugMode) {
      debugPrint(
        'Mapbox: MAPBOX_ACCESS_TOKEN not set — rotate/3D map disabled. '
        'Pass --dart-define-from-file=.dart_defines.json',
      );
    }
    return;
  }
  final token = MapConfig.mapboxAccessToken;
  MapboxOptions.setAccessToken(token);
  for (var i = 0; i < 40; i++) {
    try {
      final current = await MapboxOptions.getAccessToken();
      if (current == token) {
        if (kDebugMode) {
          debugPrint('Mapbox: access token ready (len=${token.length})');
        }
        return;
      }
    } catch (_) {
      // Platform channel may not be ready yet on the first ticks.
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (kDebugMode) {
    debugPrint('Mapbox: timed out waiting for access token acknowledgement');
  }
}

class MesozoicaApp extends StatelessWidget {
  const MesozoicaApp({
    super.key,
    required this.themeController,
    required this.catalogModeController,
  });

  final ThemeController themeController;
  final CatalogModeController catalogModeController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: catalogModeController),
        ChangeNotifierProvider(create: (_) => SplashHoldProvider()),
        ChangeNotifierProvider(
          create: (_) => AuthController()..initialize(),
        ),
        ChangeNotifierProvider(create: (_) => NotificationController()),
        ChangeNotifierProvider(create: (_) => DinosaurCatalogController()),
        ChangeNotifierProvider(
          create: (context) => FossilCatalogController(
            catalogModeController: context.read<CatalogModeController>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => SiteCatalogController(
            catalogModeController: context.read<CatalogModeController>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ToolCatalogController()),
        ChangeNotifierProvider(create: (_) => PhyloTreeController()),
        ChangeNotifierProvider(
          create: (context) => MapController(
            catalogModeController: context.read<CatalogModeController>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => LocationService()),
        ChangeNotifierProvider(create: (_) => FieldSessionCoordinator()),
        ChangeNotifierProvider(create: (_) => FieldDiscoveryCoordinator()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeController, _) {
          return MaterialApp(
            title: 'Mesozoica',
            debugShowCheckedModeBanner: AppConfig.isDebugMode,
            theme: MesozoicaTheme.light,
            darkTheme: MesozoicaTheme.dark,
            themeMode: themeController.themeMode,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
