import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import '../../services/secret_storage.dart';
import 'package:path/path.dart' as p;

/// Handles AES-256-GCM encryption for private body photos.
///
/// Key lifecycle:
///  - On first use a 256-bit key is generated and stored in flutter_secure_storage.
///  - Each file gets its own 12-byte IV, stored in the BodyPhotos table.
///  - Encrypted bytes are written to `vault/photos/private/<id>.enc`
///  - Decryption happens in memory only – no cleartext is ever written to disk.
class PhotoEncryptionService {
  static const _keyStorageKey = 'lifeos_photo_key_v1';

  static final _algo = AesGcm.with256bits();

  /// Returns (or creates) the vault-wide photo key.
  /// Storage goes through [SecretStorage] — Keystore/Keychain on mobile,
  /// app preferences on macOS (see SecretStorage for the rationale).
  static Future<SecretKey> _getOrCreateKey() async {
    final stored = await SecretStorage.read(_keyStorageKey);
    if (stored != null) {
      final bytes = base64.decode(stored);
      return SecretKey(bytes);
    }
    final key = await _algo.newSecretKey();
    final bytes = await key.extractBytes();
    await SecretStorage.write(_keyStorageKey, base64.encode(bytes));
    return key;
  }

  /// Encrypts [plainBytes] and writes them to [destPath].
  /// Returns the base64-encoded IV string (store in DB).
  static Future<String> encryptToFile(
      Uint8List plainBytes, String destPath) async {
    final key = await _getOrCreateKey();
    final nonce = _algo.newNonce();
    final secretBox = await _algo.encrypt(plainBytes, secretKey: key, nonce: nonce);

    // File layout: [MAC (16 bytes)] [ciphertext]
    final fileBytes = Uint8List.fromList([
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ]);
    await File(destPath).writeAsBytes(fileBytes);
    return base64.encode(nonce);
  }

  /// Reads [srcPath], decrypts with [ivBase64] and returns the plaintext bytes.
  static Future<Uint8List> decryptFromFile(
      String srcPath, String ivBase64) async {
    final key = await _getOrCreateKey();
    final fileBytes = await File(srcPath).readAsBytes();

    // Split file: first 16 bytes = MAC, rest = ciphertext
    final mac = Mac(fileBytes.sublist(0, 16));
    final cipherText = fileBytes.sublist(16);
    final nonce = base64.decode(ivBase64);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plain = await _algo.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(plain);
  }

  /// Ensures `vault/photos/private/` exists and contains a `.nomedia` file.
  static Future<String> ensurePrivateDir(String vaultPath) async {
    final dir = Directory(p.join(vaultPath, 'photos', 'private'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final nomedia = File(p.join(dir.path, '.nomedia'));
    if (!nomedia.existsSync()) {
      await nomedia.create();
    }
    return dir.path;
  }

  /// Deletes the encrypted `.enc` file for a photo entry.
  static Future<void> deleteFile(String vaultPath, String relPath) async {
    final full = p.join(vaultPath, relPath);
    final f = File(full);
    if (f.existsSync()) await f.delete();
  }
}
