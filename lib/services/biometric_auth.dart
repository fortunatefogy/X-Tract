import 'package:local_auth/local_auth.dart';

enum BiometricOutcome { success, failed, unavailable, error }

/// Thin wrapper around local_auth so every lock screen behaves the same.
class BiometricAuth {
  BiometricAuth._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static bool _authenticating = false;
  static DateTime? _completedAt;

  /// True while a biometric prompt is on screen.
  static bool get isAuthenticating => _authenticating;

  /// True briefly after a prompt closes. The prompt pauses/resumes the
  /// activity, so callers ignore those lifecycle events to avoid re-locking
  /// immediately after a successful unlock.
  static bool get justAuthenticated {
    final completed = _completedAt;
    return completed != null &&
        DateTime.now().difference(completed) <
            const Duration(milliseconds: 1500);
  }

  static Future<BiometricOutcome> authenticate(String reason) async {
    _authenticating = true;
    try {
      final supported =
          await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
      final BiometricOutcome outcome;
      if (!supported) {
        outcome = BiometricOutcome.unavailable;
      } else {
        final ok = await _auth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
        outcome = ok ? BiometricOutcome.success : BiometricOutcome.failed;
      }
      if (outcome == BiometricOutcome.success) {
        _completedAt = DateTime.now();
      }
      return outcome;
    } catch (_) {
      return BiometricOutcome.error;
    } finally {
      _authenticating = false;
    }
  }
}
