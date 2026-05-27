import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

const _uuid = Uuid();

/// Watches all photos for [entityId], ordered by creation time.
final entityPhotosProvider =
    StreamProvider.family<List<EntityPhoto>, String>((ref, entityId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchEntityPhotos(entityId);
});

final entityPhotoOpsProvider =
    AsyncNotifierProvider<EntityPhotoOpsNotifier, void>(
        EntityPhotoOpsNotifier.new);

class EntityPhotoOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;
  String get _vaultPath => ref.read(vaultPathProvider)!;

  /// Picks a photo from [source], copies it to `photos/<uuid>.jpg` inside the
  /// vault, and inserts a DB row for ([entityId], [entityType]).
  Future<void> addPhoto({
    required String entityId,
    required String entityType,
    required ImageSource source,
    String? caption,
  }) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 85);
    if (xfile == null) return;

    const maxBytes = 25 * 1024 * 1024; // 25 MB
    final size = await xfile.length();
    if (size > maxBytes) {
      throw Exception('Foto zu groß (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Maximal 25 MB erlaubt.');
    }

    final id = _uuid.v4();
    final photosDir = Directory(p.join(_vaultPath, 'photos'));
    if (!photosDir.existsSync()) photosDir.createSync(recursive: true);

    final dest = p.join(photosDir.path, '$id.jpg');
    await xfile.saveTo(dest);

    final relPath = p.join('photos', '$id.jpg');

    await _db.insertEntityPhoto(EntityPhotosCompanion.insert(
      id: id,
      entityId: entityId,
      entityType: entityType,
      photoPath: relPath,
      caption: Value(caption),
    ));
    ref.invalidate(entityPhotosProvider(entityId));
  }

  Future<void> deletePhoto(EntityPhoto photo) async {
    final fullPath = p.join(_vaultPath, photo.photoPath);
    final file = File(fullPath);
    if (file.existsSync()) await file.delete();
    await _db.deleteEntityPhoto(photo.id);
    ref.invalidate(entityPhotosProvider(photo.entityId));
  }

  Future<void> updateCaption(EntityPhoto photo, String? caption) async {
    await _db.updateEntityPhotoCaption(photo.id, caption);
    ref.invalidate(entityPhotosProvider(photo.entityId));
  }
}
