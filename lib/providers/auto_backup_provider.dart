import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auto_backup_service.dart';
import 'settings_provider.dart';
import 'vault_provider.dart';

/// Side-effect provider: runs a due auto-backup on vault open and re-checks
/// every 6 hours while the app is running. Kept alive in main.dart.
final autoBackupProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
  final vaultPath = ref.watch(vaultPathProvider);
  final settings = ref.watch(settingsProvider).valueOrNull;
  if (db == null ||
      vaultPath == null ||
      settings == null ||
      !settings.autoBackupEnabled) {
    return;
  }

  Future<void> run() => AutoBackupService.runIfDue(
        db: db,
        vaultPath: vaultPath,
        intervalDays: settings.autoBackupIntervalDays,
      );

  run();
  final timer = Timer.periodic(const Duration(hours: 6), (_) => run());
  ref.onDispose(timer.cancel);
});
