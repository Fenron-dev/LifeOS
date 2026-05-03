import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps local_auth to provide biometric / device-PIN authentication
/// for the private "Ich"-Tab.
class AppLockService {
  static final _auth = LocalAuthentication();

  /// Returns true if the device supports biometrics or device PIN.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the user to authenticate.
  /// Returns true on success, false on failure or cancellation.
  static Future<bool> authenticate({
    String reason = 'Bitte authentifiziere dich, um den privaten Bereich zu öffnen.',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
