import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'services/settings_service.dart';

class LinkyApp extends StatelessWidget {
  const LinkyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Linky',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5267E8),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF7F8FC),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: Colors.white,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5267E8),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
