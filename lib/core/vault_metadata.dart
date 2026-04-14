import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// How a vault's database is encrypted.
enum VaultEncryptionMode {
  /// Plain SQLite — no encryption at rest. Used by legacy vaults.
  none,

  /// SQLCipher with a random key stored in the OS keychain. Convenient
  /// (no prompt) but the key does not travel with the vault folder.
  keystore,

  /// SQLCipher with a key derived from a user password. Fully portable —
  /// the password lives only in the user's head.
  password,
}

/// Persisted at the vault root as `vault.json`.
class VaultMetadata {
  static const _fileName = 'vault.json';
  static const _currentVersion = 1;

  final int version;
  final VaultEncryptionMode encryption;
  final DateTime createdAt;

  /// PBKDF2 salt (base64) — only present for [VaultEncryptionMode.password].
  final String? passwordSalt;

  const VaultMetadata({
    this.version = _currentVersion,
    required this.encryption,
    required this.createdAt,
    this.passwordSalt,
  });

  /// Loads metadata from the vault directory. Returns `null` if the file is
  /// missing — the caller should treat that as a legacy unencrypted vault
  /// (i.e. fall back to [VaultEncryptionMode.none]).
  static Future<VaultMetadata?> load(String vaultPath) async {
    final file = File(p.join(vaultPath, _fileName));
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return VaultMetadata(
      version: json['version'] as int? ?? _currentVersion,
      encryption: _parseMode(json['encryption'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      passwordSalt: json['passwordSalt'] as String?,
    );
  }

  Future<void> save(String vaultPath) async {
    final file = File(p.join(vaultPath, _fileName));
    await file.writeAsString(jsonEncode({
      'version': version,
      'encryption': encryption.name,
      'createdAt': createdAt.toIso8601String(),
      if (passwordSalt != null) 'passwordSalt': passwordSalt,
    }));
  }

  static VaultEncryptionMode _parseMode(String? raw) {
    return VaultEncryptionMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => VaultEncryptionMode.none,
    );
  }
}
