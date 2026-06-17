import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _kVaultDbFile = 'lifeos.db';
const _kVaultPhotosDir = 'photos';
const _kVaultExportsDir = 'exports';
const _kVaultCacheDir = 'cache';

class VaultInfo {
  final String path;
  final String name;
  final DateTime lastOpened;

  const VaultInfo({
    required this.path,
    required this.name,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory VaultInfo.fromJson(Map<String, dynamic> json) => VaultInfo(
        path: json['path'] as String,
        name: json['name'] as String,
        lastOpened: DateTime.parse(json['lastOpened'] as String),
      );
}

class VaultManager {
  VaultManager._();

  /// Validates a path as a usable vault (creates required subdirs if needed).
  static Future<bool> initializeVault(String vaultPath) async {
    try {
      final dir = Directory(vaultPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      await Directory(p.join(vaultPath, _kVaultPhotosDir)).create(recursive: true);
      await Directory(p.join(vaultPath, _kVaultExportsDir)).create(recursive: true);
      await Directory(p.join(vaultPath, _kVaultCacheDir)).create(recursive: true);
      return true;
    } catch (e) {
      debugPrint('VaultManager: failed to initialize vault at $vaultPath: $e');
      return false;
    }
  }

  /// Returns true if the folder looks like a valid vault (has lifeos.db OR is empty).
  static bool isValidVaultFolder(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return false;
    final dbFile = File(p.join(path, _kVaultDbFile));
    // Accept if DB exists, or if folder is empty (will be initialized)
    return dbFile.existsSync() ||
        dir.listSync().isEmpty;
  }

  /// Full path to the DB file inside a vault.
  static String dbPath(String vaultPath) => p.join(vaultPath, _kVaultDbFile);

  /// Full path to the photos directory.
  static String photosPath(String vaultPath) => p.join(vaultPath, _kVaultPhotosDir);

  /// Full path to the cache directory (thumbnails etc.).
  static String cachePath(String vaultPath) => p.join(vaultPath, _kVaultCacheDir);

  /// Full path to the exports directory.
  static String exportsPath(String vaultPath) => p.join(vaultPath, _kVaultExportsDir);

  /// Returns the vault name: last path segment.
  static String vaultName(String vaultPath) => p.basename(vaultPath);

  /// Default vault location.
  ///
  /// - Android / iOS / macOS: app sandbox container (always writable).
  /// - Linux / Windows: ~/Documents/lifeos-haushalt (no sandbox).
  static Future<String> defaultVaultPath() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'lifeos-vault');
    }
    // Linux / Windows: user's Documents folder.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        (await getApplicationDocumentsDirectory()).path;
    return p.join(home, 'Documents', 'lifeos-haushalt');
  }
}
