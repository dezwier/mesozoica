import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'controllers/dinosaur_catalog_controller.dart';
import 'shell/app_shell.dart';
import 'theme/mesozoica_theme.dart';

void main() {
  runApp(const MesozoicaApp());
}

class MesozoicaApp extends StatelessWidget {
  const MesozoicaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DinosaurCatalogController()),
      ],
      child: MaterialApp(
        title: 'Mesozoica',
        debugShowCheckedModeBanner: AppConfig.isDebugMode,
        theme: MesozoicaTheme.light,
        darkTheme: MesozoicaTheme.dark,
        themeMode: MesozoicaTheme.defaultThemeMode,
        home: const AppShell(),
      ),
    );
  }
}
