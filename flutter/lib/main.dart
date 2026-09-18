import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/mapbox_access.dart';
import 'controllers/catalog_mode_controller.dart';
import 'controllers/theme_controller.dart';
import 'core/di/app_providers.dart';
import 'core/networking/token_storage.dart';
import 'features/game_config/data/game_config_asset_loader.dart';
import 'features/notifications/presentation/celebration_host.dart';
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
  await configureMapboxAccessToken();
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
              return CelebrationHost(
                child: Stack(
                  fit: StackFit.expand,
                  children: [?child, const XpAwardOverlay()],
                ),
              );
            },
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
