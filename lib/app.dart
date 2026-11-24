import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';

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
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        AppAccent.current = AppAccent.byId(settings.accentColor);
        return MaterialApp(
          title: 'Comet',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeOutCubic,
          scrollBehavior: const _CometScrollBehavior(),
          builder: (context, child) => _AppLockGate(child: child),
          home: startInShareMode
              ? ShareHost(
                  startInShareMode: true,
                  initialText: initialShareText,
                )
              : AnimatedSplashScreen(
                  splash: const _SplashBrand(),
                  nextScreen: const ShareHost(),
                  backgroundColor: const Color(0xFF0F1017),
                  duration: 900,
                  animationDuration: const Duration(milliseconds: 400),
                  splashTransition: SplashTransition.fadeTransition,
                  pageTransitionType: PageTransitionType.fade,
                  splashIconSize: 260,
                ),
        );
      },
    );
  }
}

class _SplashBrand extends StatelessWidget {
  const _SplashBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const ClipOval(
          child: Image(
            image: AssetImage('assets/icon/cropped_circle_image.png'),
            width: 120,
            height: 120,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Comet',
          style: AppText.display(34, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          'Browse. Detect. Save.',
          style: AppText.body(13, color: const Color(0xFF9AA1B2)),
        ),
      ],
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
              Icon(Icons.fingerprint_rounded,
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
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
