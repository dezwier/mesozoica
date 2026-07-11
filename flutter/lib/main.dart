import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const MesozoicaApp());
}

class MesozoicaApp extends StatelessWidget {
  const MesozoicaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesozoica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C6B4A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
