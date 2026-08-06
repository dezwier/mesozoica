import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/map_config.dart';
import 'controllers/catalog_mode_controller.dart';
import 'controllers/theme_controller.dart';
import 'core/di/app_providers.dart';
import 'core/networking/token_storage.dart';
import 'features/game_config/data/game_config_asset_loader.dart';
import 'firebase_options.dart';
import 'services/map_tile_cache.dart';
import 'services/push_notification_runtime.dart';
import 'shell/app_navigator.dart';
import 'shell/app_shell.dart';
import 'theme/mesozoica_theme.dart';
import 'widgets/common/app_splash_screen.dart';
import 'widgets/xp/xp_award_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use the native-picked splash dinosaur so system + Flutter match.
  await AppSplashScreen.prepare();
  await GameConfigAssetLoader.load();
  await TokenStorage.reloadToken();
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
  runApp(
    MesozoicaApp(
      themeController: themeController,
      catalogModeController: catalogModeController,
    ),
  );
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
      providers: buildAppProviders(
        themeController: themeController,
        catalogModeController: catalogModeController,
      ),
      child: Consumer<ThemeController>(
        builder: (context, themeController, _) {
          return MaterialApp(
            title: 'Mesozoica',
            navigatorKey: appNavigatorKey,
            debugShowCheckedModeBanner: AppConfig.isDebugMode,
            theme: MesozoicaTheme.light,
            darkTheme: MesozoicaTheme.dark,
            themeMode: themeController.themeMode,
            builder: (context, child) {
              // Above the root Navigator so drawers / sheets / dialogs
              // never cover the XP badge.
              return Stack(
                fit: StackFit.expand,
                children: [?child, const XpAwardOverlay()],
              );
            },
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
