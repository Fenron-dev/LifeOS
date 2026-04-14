import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';

import '../services/secret_storage.dart';
import 'vault_metadata.dart';

/// Resolves the SQLCipher encryption key for a vault.
///
/// - [VaultEncryptionMode.none]    → returns `null` (open as plain SQLite)
/// - [VaultEncryptionMode.keystore] → reads a random key from the OS keychain
///                                    (key id = stable hash of the vault path)
/// - [VaultEncryptionMode.password] → derives the key via PBKDF2-HMAC-SHA256
///                                    from the user-supplied password + salt
class VaultKeyService {
  VaultKeyService._();

  static const _pbkdf2Iterations = 200000;
  static const _keyBytes = 32; // 256-bit key for SQLCipher
  static const _saltBytes = 16;

  /// Resolves the key for an existing vault. For password mode the caller must
  /// supply the password (e.g. via an unlock prompt).
  static Future<String?> resolveKey({
    required String vaultPath,
    required VaultMetadata metadata,
    String? password,
  }) async {
    switch (metadata.encryption) {
      case VaultEncryptionMode.none:
        return null;
      case VaultEncryptionMode.keystore:
        final stored = await SecretStorage.read(_keystoreId(vaultPath));
        if (stored == null) {
          throw StateError(
              'Keystore-Schlüssel für Vault nicht gefunden: $vaultPath');
        }
        return stored;
      case VaultEncryptionMode.password:
        if (password == null || password.isEmpty) {
          throw ArgumentError('Passwort erforderlich');
        }
        if (metadata.passwordSalt == null) {
          throw StateError('Vault-Metadaten ohne Salt — beschädigt');
        }
        return _derive(password, base64Decode(metadata.passwordSalt!));
    }
  }

  /// Sets up encryption for a brand-new vault and returns both the metadata
  /// (already containing the salt for password mode) and the resulting key.
  static Future<({VaultMetadata metadata, String? key})> initializeForNewVault({
    required String vaultPath,
    required VaultEncryptionMode mode,
    String? password,
  }) async {
    final now = DateTime.now();
    switch (mode) {
      case VaultEncryptionMode.none:
        return (
          metadata: VaultMetadata(encryption: mode, createdAt: now),
          key: null,
        );
      case VaultEncryptionMode.keystore:
        final key = _randomHexKey();
        await SecretStorage.write(_keystoreId(vaultPath), key);
        return (
          metadata: VaultMetadata(encryption: mode, createdAt: now),
          key: key,
        );
      case VaultEncryptionMode.password:
        if (password == null || password.isEmpty) {
          throw ArgumentError('Passwort erforderlich');
        }
        final salt = _randomBytes(_saltBytes);
        final derived = await _derive(password, salt);
        return (
          metadata: VaultMetadata(
            encryption: mode,
            createdAt: now,
            passwordSalt: base64Encode(salt),
          ),
          key: derived,
        );
    }
  }

  /// Removes the keystore entry for a vault (if any). Call when deleting
  /// or forgetting a vault to avoid orphaned keychain entries.
  static Future<void> forgetKeystoreEntry(String vaultPath) =>
      SecretStorage.delete(_keystoreId(vaultPath));

  // ── internals ──────────────────────────────────────────────────────────

  /// SecretStorage key for a given vault path. Stable across runs so the
  /// same vault folder always resolves to the same keychain entry.
  static String _keystoreId(String vaultPath) {
    final digest = sha256.convert(utf8.encode(vaultPath));
    return 'lifeos_vault_key_${digest.toString().substring(0, 16)}';
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static String _randomHexKey() {
    final bytes = _randomBytes(_keyBytes);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> _derive(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: _keyBytes * 8,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
