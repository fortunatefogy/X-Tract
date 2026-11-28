import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';

import 'features/share/share_host.dart';
import 'services/biometric_auth.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

class _CometScrollBehavior extends MaterialScrollBehavior {
  const _CometScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class CometApp extends StatelessWidget {
  const CometApp({
    super.key,
    this.startInShareMode = false,
    this.initialShareText,
  });

  final bool startInShareMode;
  final String? initialShareText;

  @override
  Widget build(BuildContext context) => _ThemedApp(
        startInShareMode: startInShareMode,
        initialShareText: initialShareText,
      );
}

/// Rebuilds [MaterialApp] only when the theme or accent actually changes, so
/// unrelated settings writes (detection toggles, download options, ...) no
/// longer rebuild the entire widget tree.
class _ThemedApp extends StatefulWidget {
  const _ThemedApp({required this.startInShareMode, this.initialShareText});

  final bool startInShareMode;
  final String? initialShareText;

  @override
  State<_ThemedApp> createState() => _ThemedAppState();
}

class _ThemedAppState extends State<_ThemedApp> {
  static const _maxTextScale = 1.3;

  late ThemeMode _themeMode;
  late String _accentColor;

  @override
  void initState() {
    super.initState();
    final settings = SettingsService.instance;
    _themeMode = settings.themeMode;
    _accentColor = settings.accentColor;
    settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    final settings = SettingsService.instance;
    if (settings.themeMode == _themeMode &&
        settings.accentColor == _accentColor) {
      return;
    }
    setState(() {
      _themeMode = settings.themeMode;
      _accentColor = settings.accentColor;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppAccent.current = AppAccent.byId(_accentColor);
    return MaterialApp(
      title: 'Comet',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeOutCubic,
      scrollBehavior: const _CometScrollBehavior(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: _maxTextScale),
          ),
          child: _AppLockGate(child: child),
        );
      },
      home: widget.startInShareMode
          ? ShareHost(
              startInShareMode: true,
              initialText: widget.initialShareText,
            )
          : const ShareHost(),
    );
  }
}

class _AppLockGate extends StatefulWidget {
  const _AppLockGate({required this.child});

  final Widget? child;

  @override
  State<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<_AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _authenticating = false;
  bool _backgrounded = false;
  bool _enabledWhenLastBuilt = false;
  String? _authError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enabledWhenLastBuilt = SettingsService.instance.appLockEnabled;
    if (_enabledWhenLastBuilt) {
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Biometric prompts only move the app to `inactive`. Locking on every
    // resume would re-lock immediately after a successful unlock, so only
    // treat a genuine background (`paused`/`hidden`) as leaving the app.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // A biometric prompt pauses the activity too; do not treat that as the
      // user leaving the app or we would re-lock right after unlocking.
      if (!BiometricAuth.isAuthenticating && !BiometricAuth.justAuthenticated) {
        _backgrounded = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_backgrounded) {
        _backgrounded = false;
        if (SettingsService.instance.appLockEnabled &&
            !BiometricAuth.isAuthenticating &&
            !BiometricAuth.justAuthenticated) {
          _lock();
        }
      }
    }
  }

  void _lock() {
    if (!mounted || _locked) return;
    setState(() => _locked = true);
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating || !mounted) return;
    _authenticating = true;
    final outcome = await BiometricAuth.authenticate(
      'Confirm your identity to open Comet.',
    );
    _authenticating = false;
    if (!mounted) return;
    setState(() {
      _locked = outcome != BiometricOutcome.success;
      _authError = outcome == BiometricOutcome.unavailable
          ? 'No fingerprint, face, or screen lock is set up on this device. '
              'Set a screen lock in system settings, then tap Unlock.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    if (settings.appLockEnabled && !_enabledWhenLastBuilt) {
      _enabledWhenLastBuilt = true;
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    } else if (!settings.appLockEnabled) {
      _enabledWhenLastBuilt = false;
      _locked = false;
    }
    final palette = context.palette;
    if (!_locked || !settings.appLockEnabled) {
      return widget.child ?? const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedFingerPrint,
                  size: 64, color: palette.foreground),
              const SizedBox(height: 18),
              Text('Comet is locked',
                  style: AppText.display(24, color: palette.foreground)),
              const SizedBox(height: 6),
              Text(
                'Confirm your fingerprint or screen lock to continue.',
                textAlign: TextAlign.center,
                style: AppText.body(13, color: palette.mutedForeground),
              ),
              if (_authError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _authError!,
                  textAlign: TextAlign.center,
                  style: AppText.body(11, color: palette.destructive),
                ),
              ],
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: _authenticate,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedLockOpen),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
