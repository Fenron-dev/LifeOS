import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'backup_service.dart';

/// Time-based automatic vault backups with retention.
///
/// Destination is a sibling folder of the vault (`<vault>-backups`) so the
/// backup survives vault corruption but needs no directory picker.
class AutoBackupService {
  static const _lastRunKey = 'last_auto_backup_at';
  static const keepCount = 5;

  /// Creates a backup when the last one is older than [intervalDays].
  /// Returns the created file, or null when not due / on failure.
  static Future<File?> runIfDue({
    required AppDatabase db,
    required String vaultPath,
    required int intervalDays,
  }) async {
    try {
      final lastRaw = await db.getSetting(_lastRunKey);
      final last = DateTime.tryParse(lastRaw ?? '');
      final now = DateTime.now();
      if (last != null && now.difference(last).inDays < intervalDays) {
        return null;
      }

      final destDir = '$vaultPath-backups';
      await Directory(destDir).create(recursive: true);
      final file = await BackupService.createBackup(vaultPath, destDir);
      await db.setSetting(_lastRunKey, now.toIso8601String());

      // Retention: filename embeds the timestamp, so lexicographic order
      // equals chronological order — keep the newest [keepCount].
      final backups = Directory(destDir)
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('lifeos-backup-'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final old in backups.skip(keepCount)) {
        try {
          old.deleteSync();
        } catch (_) {
          // Retention failure must never break the backup itself.
        }
      }
      return file;
    } catch (_) {
      return null; // backup is best-effort; never crash the app over it
    }
  }
}
