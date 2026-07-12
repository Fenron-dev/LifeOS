import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around [FlutterSecureStorage] for credentials that must not
/// be stored in plain `SharedPreferences` (API tokens, future sync keys, ...).
///
/// On first read, falls back to the legacy SharedPreferences key — if found,
/// it is migrated into secure storage and the plaintext copy is removed.
class SecretStorage {
  SecretStorage._();

  // Android Keystore, iOS Keychain, Linux libsecret — defaults are fine.
  // macOS: the data-protection keychain (default since v9) requires the
  // keychain-access-groups entitlement, which needs a paid dev certificate —
  // ad-hoc-signed local builds fail with errSecMissingEntitlement (-34018).
  // The classic login keychain works without it and is equally encrypted.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  /// macOS: kein Keychain. Ad-hoc-signierte Builds erzeugen bei jedem
  /// Rebuild eine neue Signatur — der Schlüsselbund fragt dann jedes Mal
  /// nach Zugriff (bzw. wirft -34018/-128). Für eine lokale Desktop-App
  /// sind die App-Preferences der pragmatische Kompromiss.
  static bool get _useKeychain => !Platform.isMacOS;

  static String _prefsKey(String key) => 'secret_$key';

  /// Reads a secret, optionally migrating from a legacy SharedPreferences key.
  static Future<String?> read(
    String key, {
    String? legacyPrefsKey,
  }) async {
    if (!_useKeychain) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey(key)) ??
          (legacyPrefsKey != null ? prefs.getString(legacyPrefsKey) : null);
    }
    final existing = await _storage.read(key: key);
    if (existing != null) return existing;

    if (legacyPrefsKey != null) {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(legacyPrefsKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _storage.write(key: key, value: legacy);
        await prefs.remove(legacyPrefsKey);
        return legacy;
      }
    }
    return null;
  }

  static Future<void> write(String key, String value) async {
    if (!_useKeychain) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey(key), value);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  static Future<void> delete(String key) async {
    if (!_useKeychain) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey(key));
      return;
    }
    await _storage.delete(key: key);
  }
}
