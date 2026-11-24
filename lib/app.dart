import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'features/share/share_host.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

class _LinkyScrollBehavior extends MaterialScrollBehavior {
  const _LinkyScrollBehavior();

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
      builder: (context, _) {
        AppAccent.current = AppAccent.byId(settings.accentColor);
        return MaterialApp(
          title: 'Linky',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeOutCubic,
          scrollBehavior: const _LinkyScrollBehavior(),
          builder: (context, child) => _AppLockGate(child: child),
          home: ShareHost(
            startInShareMode: startInShareMode,
            initialText: initialShareText,
          ),
        );
      },
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
  final _auth = LocalAuthentication();
  bool _locked = false;
  bool _authenticating = false;
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
    if (state == AppLifecycleState.resumed &&
        SettingsService.instance.appLockEnabled) {
      _lock();
    }
  }

  void _lock() {
    if (!mounted || _locked) {
      if (_locked) _authenticate();
      return;
    }
    setState(() => _locked = true);
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating || !mounted) return;
    _authenticating = true;
    try {
      final canCheck =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canCheck) {
        if (mounted) {
          setState(() => _authError =
              'No fingerprint, face, or screen lock is set up on this device. '
                  'Set a screen lock in system settings, then tap Unlock.');
        }
        return;
      }
      final unlocked = await _auth.authenticate(
        localizedReason: 'Confirm your identity to open Linky.',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (unlocked && mounted) setState(() => _locked = false);
    } catch (_) {
    } finally {
      _authenticating = false;
    }
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
              Text('Linky is locked',
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
