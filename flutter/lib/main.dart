import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'controllers/auth_controller.dart';
import 'controllers/dinosaur_catalog_controller.dart';
import 'controllers/fossil_catalog_controller.dart';
import 'controllers/map_controller.dart';
import 'controllers/phylo_tree_controller.dart';
import 'controllers/site_catalog_controller.dart';
import 'controllers/theme_controller.dart';
import 'firebase_options.dart';
import 'services/location_service.dart';
import 'shell/app_shell.dart';
import 'theme/mesozoica_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Firebase init skipped/failed: $error');
    }
  }
  runApp(const MesozoicaApp());
}

class MesozoicaApp extends StatelessWidget {
  const MesozoicaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(
          create: (_) => AuthController()..initialize(),
        ),
        ChangeNotifierProvider(create: (_) => DinosaurCatalogController()),
        ChangeNotifierProvider(create: (_) => FossilCatalogController()),
        ChangeNotifierProvider(create: (_) => SiteCatalogController()),
        ChangeNotifierProvider(create: (_) => PhyloTreeController()),
        ChangeNotifierProvider(create: (_) => MapController()),
        ChangeNotifierProvider(create: (_) => LocationService()),
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
