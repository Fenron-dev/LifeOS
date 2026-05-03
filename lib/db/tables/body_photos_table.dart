import 'package:drift/drift.dart';

/// Phase 6.7 – Private encrypted body photos.
/// File bytes are stored as AES-256-GCM encrypted blobs in
/// `vault/photos/private/<id>.enc` – only metadata lives in this table.
class BodyPhotos extends Table {
  TextColumn get id => text()();
  DateTimeColumn get takenAt => dateTime()();
  /// front|side|back|face|other
  TextColumn get photoType => text().withDefault(const Constant('other'))();
  /// Relative path from vault root: `photos/private/<id>.enc`
  TextColumn get filePathRelative => text()();
  /// Per-file IV used for AES-256-GCM (base64-encoded, 12 bytes)
  TextColumn get encryptionIv => text()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  /// Weight snapshot at photo time (nullable)
  RealColumn get weightAtPhotoKg => real().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
