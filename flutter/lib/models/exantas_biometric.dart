import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import '../mobile/ui/ex_app_lock.dart';
import '../mobile/ui/exantas_strings.dart';
import 'platform_model.dart';

/// Local (per-device) option. Default off. UI gate only: never read by, or
/// copied into, any Office token, outbox or native-auth code.
const String kExantasBiometricUnlock = 'exantas.biometric_unlock';

bool exantasBiometricEnabled() =>
    bind.mainGetLocalOption(key: kExantasBiometricUnlock) == 'Y';

Future<void> exantasSetBiometricEnabled(bool on) => bind.mainSetLocalOption(
    key: kExantasBiometricUnlock, value: on ? 'Y' : '');

final LocalAuthentication _auth = LocalAuthentication();

Future<bool> exantasBiometricSupported() async {
  try {
    return await _auth.isDeviceSupported();
  } catch (_) {
    return false;
  }
}

/// One system prompt: biometric or device credential (PIN/pattern/password).
Future<ExAuthResult> exantasAuthenticate() async {
  try {
    final ok = await _auth.authenticate(
        localizedReason: ExStrings.biometricReason,
        authMessages: const [
          AndroidAuthMessages(
              signInTitle: ExStrings.biometricUnlock,
              biometricHint: '',
              cancelButton: ExStrings.cancel),
        ],
        // Platform dialogs only; no AppCompat error dialogs.
        options: const AuthenticationOptions(
            stickyAuth: true, useErrorDialogs: false));
    return ok ? ExAuthResult.success : ExAuthResult.failed;
  } on PlatformException catch (e) {
    switch (e.code) {
      case 'NotAvailable':
      case 'NotEnrolled':
      case 'PasscodeNotSet':
      // Misconfigured host activity: never lock the user out of the app.
      case 'no_fragment_activity':
        return ExAuthResult.unavailable;
      case 'LockedOut':
      case 'PermanentlyLockedOut':
        return ExAuthResult.lockedOut;
      default:
        return ExAuthResult.failed;
    }
  }
}

/// App-wide controller (Android only; created lazily by main).
final ExAppLockController exantasAppLock = ExAppLockController(
    isEnabled: exantasBiometricEnabled, authenticate: exantasAuthenticate);
