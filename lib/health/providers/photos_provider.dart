import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';
import '../services/photo_encryption_service.dart';

const _uuid = Uuid();

final bodyPhotosProvider = StreamProvider<List<BodyPhoto>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAllBodyPhotos();
});

final photoOpsProvider =
    AsyncNotifierProvider<PhotoOpsNotifier, void>(PhotoOpsNotifier.new);

class PhotoOpsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;
  String get _vaultPath => ref.read(vaultPathProvider)!;

  /// Pick a photo from gallery or camera, encrypt and store it.
  Future<void> addPhoto({
    required ImageSource source,
    required String photoType,
    String? notes,
    double? weightAtPhotoKg,
  }) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 85);
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    final id = _uuid.v4();
    final privateDir =
        await PhotoEncryptionService.ensurePrivateDir(_vaultPath);
    final destPath = p.join(privateDir, '$id.enc');
    final relPath = p.join('photos', 'private', '$id.enc');

    final iv =
        await PhotoEncryptionService.encryptToFile(Uint8List.fromList(bytes), destPath);

    await _db.insertBodyPhoto(BodyPhotosCompanion.insert(
      id: id,
      takenAt: DateTime.now(),
      photoType: Value(photoType),
      filePathRelative: relPath,
      encryptionIv: iv,
      fileSizeBytes: Value(bytes.length),
      weightAtPhotoKg: Value(weightAtPhotoKg),
      notes: Value(notes),
    ));
    ref.invalidate(bodyPhotosProvider);
  }

  /// Decrypts and returns raw image bytes for display.
  Future<Uint8List?> loadPhotoBytes(BodyPhoto photo) async {
    final fullPath = p.join(_vaultPath, photo.filePathRelative);
    if (!File(fullPath).existsSync()) return null;
    return PhotoEncryptionService.decryptFromFile(fullPath, photo.encryptionIv);
  }

  Future<void> deletePhoto(BodyPhoto photo) async {
    await PhotoEncryptionService.deleteFile(_vaultPath, photo.filePathRelative);
    await _db.deleteBodyPhoto(photo.id);
    ref.invalidate(bodyPhotosProvider);
  }

  Future<void> updateNotes(String id, String? notes) async {
    await _db.updateBodyPhotoNotes(id, notes);
    ref.invalidate(bodyPhotosProvider);
  }
}
