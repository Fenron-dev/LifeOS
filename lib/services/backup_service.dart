import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class BackupService {
  /// Creates a zip backup of [vaultPath] and writes it to [destDir].
  /// Returns the created [File].
  static Future<File> createBackup(String vaultPath, String destDir) async {
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final zipPath = p.join(destDir, 'lifeos-backup-$timestamp.zip');

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    final vaultDir = Directory(vaultPath);
    await for (final entity in vaultDir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: vaultPath);
        encoder.addFile(entity, relativePath);
      }
    }
    encoder.close();
    return File(zipPath);
  }

  /// Restores a backup zip to [vaultPath].
  /// The caller must close the database connection before calling this.
  static Future<void> restoreBackup(String zipPath, String vaultPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final vaultRoot = p.normalize(p.absolute(vaultPath));
    final rootWithSep = vaultRoot.endsWith(p.separator)
        ? vaultRoot
        : '$vaultRoot${p.separator}';

    for (final file in archive) {
      final entryName = file.name;
      // Reject absolute paths and any segment that escapes the vault.
      if (p.isAbsolute(entryName) ||
          p.split(entryName).any((s) => s == '..')) {
        throw FormatException('Unsicherer Pfad im Backup: $entryName');
      }
      final resolved = p.normalize(p.join(vaultRoot, entryName));
      if (resolved != vaultRoot && !resolved.startsWith(rootWithSep)) {
        throw FormatException('Unsicherer Pfad im Backup: $entryName');
      }

      if (file.isFile) {
        final outFile = File(resolved);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(resolved).create(recursive: true);
      }
    }
  }
}
