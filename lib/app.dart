import 'package:flutter/material.dart';

import 'features/share/share_host.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

class LinkyApp extends StatelessWidget {
  const LinkyApp({
    super.key,
    this.startInShareMode = false,
    this.initialShareText,
  });

  final bool startInShareMode;
  final String? initialShareText;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Linky',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeOutCubic,
        home: ShareHost(
          startInShareMode: startInShareMode,
          initialText: initialShareText,
        ),
      ),
    );
  }
}
