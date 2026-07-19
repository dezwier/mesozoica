import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
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
import 'controllers/theme_controller.dart';
import 'firebase_options.dart';
import 'services/location_service.dart';
import 'services/map_tile_cache.dart';
import 'services/push_notification_runtime.dart';
import 'shell/app_shell.dart';
import 'theme/mesozoica_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
