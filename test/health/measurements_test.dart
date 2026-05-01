import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('insert and retrieve a full body measurement', () async {
    await db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: 'm1',
      loggedAt: DateTime(2026, 5, 1, 8, 0),
      chestCm: const Value(98.5),
      waistCm: const Value(82.0),
      hipCm: const Value(103.0),
      thighCm: const Value(58.0),
      armCm: const Value(35.5),
      neckCm: const Value(38.0),
      notes: const Value('Morgens nüchtern'),
    ));

    final row = (await db.latestBodyMeasurement())!;
    expect(row.chestCm, 98.5);
    expect(row.waistCm, 82.0);
    expect(row.hipCm, 103.0);
    expect(row.thighCm, 58.0);
    expect(row.armCm, 35.5);
    expect(row.neckCm, 38.0);
    expect(row.notes, 'Morgens nüchtern');
  });

  test('partial measurement (only waist and hip) stores nulls for other fields',
      () async {
    await db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: 'm2',
      loggedAt: DateTime(2026, 5, 2),
      waistCm: const Value(81.5),
      hipCm: const Value(102.0),
    ));

    final row = (await db.latestBodyMeasurement())!;
    expect(row.waistCm, 81.5);
    expect(row.hipCm, 102.0);
    expect(row.chestCm, isNull);
    expect(row.armCm, isNull);
    expect(row.neckCm, isNull);
  });

  test('latestBodyMeasurement returns most recent by loggedAt', () async {
    await db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: 'old',
      loggedAt: DateTime(2026, 1, 1),
      waistCm: const Value(90.0),
    ));
    await db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: 'new',
      loggedAt: DateTime(2026, 5, 1),
      waistCm: const Value(85.0),
    ));

    final latest = await db.latestBodyMeasurement();
    expect(latest?.id, 'new');
    expect(latest?.waistCm, 85.0);
  });

  test('deleteBodyMeasurement removes the row', () async {
    await db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: 'del',
      loggedAt: DateTime(2026, 5, 1),
      waistCm: const Value(83.0),
    ));
    expect((await db.select(db.bodyMeasurements).get()).length, 1);

    await db.deleteBodyMeasurement('del');
    expect((await db.select(db.bodyMeasurements).get()).length, 0);
  });

  test('watchBodyMeasurements stream emits newest-first', () async {
    await db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: 'a',
      loggedAt: DateTime(2026, 3, 1),
      waistCm: const Value(88.0),
    ));
    await db.insertBodyMeasurement(BodyMeasurementsCompanion.insert(
      id: 'b',
      loggedAt: DateTime(2026, 5, 1),
      waistCm: const Value(84.0),
    ));

    final rows = await db.watchBodyMeasurements().first;
    expect(rows.first.id, 'b');
    expect(rows.last.id, 'a');
  });
}
