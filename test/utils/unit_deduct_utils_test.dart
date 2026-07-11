import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/db/database.dart';
import 'package:lifeos/utils/unit_deduct_utils.dart';

// ── Test fixtures ─────────────────────────────────────────────────────────────

UnitConversion conv(String from, String to, double factor) => UnitConversion(
      id: 'c-$from-$to',
      fromUnit: from,
      toUnit: to,
      factor: factor,
      scope: 'item',
      scopeId: null,
      notes: null,
      createdAt: DateTime(2026),
    );

Item testItem({
  String? purchaseUnit,
  double? purchaseQty,
  String? stockUnit,
}) =>
    Item(
      id: 'item-1',
      name: 'Testartikel',
      brand: null,
      ean: null,
      categoryId: 'food',
      productType: 'ingredient',
      alwaysConsumedFully: false,
      openedFlag: false,
      nutritionRefUnit: 'g',
      isFavorite: false,
      isTrashed: false,
      isStaple: false,
      expiryType: 'bestBefore',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      purchaseUnit: purchaseUnit,
      purchaseQty: purchaseQty,
      stockUnit: stockUnit,
    );

void main() {
  group('unitToGrams', () {
    test('weight/volume base units', () {
      expect(unitToGrams('g', []), 1.0);
      expect(unitToGrams('kg', []), 1000.0);
      expect(unitToGrams('ml', []), 1.0);
      expect(unitToGrams('l', []), 1000.0);
    });

    test('Stück via conversion Stück→g', () {
      expect(unitToGrams('Stück', [conv('Stück', 'g', 500)]), 500.0);
    });

    test('Packung via reverse conversion g→Packung', () {
      expect(unitToGrams('Packung', [conv('g', 'Packung', 0.002)]),
          closeTo(500.0, 0.001));
    });

    test('unknown unit without conversion → null', () {
      expect(unitToGrams('Stück', []), isNull);
    });
  });

  group('convertQty', () {
    final stk500g = [conv('Stück', 'g', 500)];

    test('identity', () {
      expect(convertQty(125, 'g', 'g', []), 125);
    });

    test('g → Stück (der gemeldete Fall: 125 g = 0,25 Stück)', () {
      expect(convertQty(125, 'g', 'Stück', stk500g), closeTo(0.25, 1e-9));
    });

    test('Stück → g', () {
      expect(convertQty(0.5, 'Stück', 'g', stk500g), closeTo(250, 1e-9));
    });

    test('kg → Stück über Gramm-Brücke', () {
      expect(convertQty(1, 'kg', 'Stück', stk500g), closeTo(2.0, 1e-9));
    });

    test('kein Pfad → null (nie stillschweigend falsch buchen)', () {
      expect(convertQty(125, 'g', 'Stück', []), isNull);
      expect(convertQty(2, 'Beutel', 'Karton', []), isNull);
    });

    test('Stück → Packung ohne Gewichtsbezug (direkte Kette)', () {
      expect(convertQty(12, 'Stück', 'Packung', [conv('Packung', 'Stück', 6)]),
          closeTo(2.0, 1e-9));
    });
  });

  group('implicitConversions (Packungs-Definition am Artikel)', () {
    test('vollständige Definition → 1 Packung = 500 g', () {
      final convs = implicitConversions(
          testItem(purchaseUnit: 'Packung', purchaseQty: 500, stockUnit: 'g'));
      expect(convs, hasLength(1));
      expect(convs.first.fromUnit, 'Packung');
      expect(convs.first.toUnit, 'g');
      expect(convs.first.factor, 500);
    });

    test('unvollständig oder degeneriert → leer', () {
      expect(implicitConversions(null), isEmpty);
      expect(implicitConversions(testItem(purchaseUnit: 'Packung')), isEmpty);
      expect(
          implicitConversions(
              testItem(purchaseUnit: 'g', purchaseQty: 1, stockUnit: 'g')),
          isEmpty);
      expect(
          implicitConversions(
              testItem(purchaseUnit: 'Packung', purchaseQty: 0, stockUnit: 'g')),
          isEmpty);
    });

    test('macht den Nutzer-Fall ohne manuelle Conversion lösbar', () {
      final item =
          testItem(purchaseUnit: 'Packung', purchaseQty: 500, stockUnit: 'g');
      final convs = resolveConversions(
          item: item, itemConvs: const [], globalConvs: const []);
      // 125 g aus einem Bestand in Packungen ausbuchen:
      expect(convertQty(125, 'g', 'Packung', convs), closeTo(0.25, 1e-9));
    });
  });

  group('buildDeductUnitOptions — diaryMode Vorbelegung (Bug U1)', () {
    final stk500g = [conv('Stück', 'g', 500)];

    test('125 g geloggt, Bestand Stück → Stück-Option = 0,25, g-Option = 125',
        () {
      final options = buildDeductUnitOptions(
        inventoryUnit: 'Stück',
        conversions: stk500g,
        fallbackQty: 1.0, // alte Heuristik hätte 1 Stück / 500 g vorbelegt
        diaryMode: true,
        requestedQty: 125,
        requestedUnit: 'g',
      );
      final stueck =
          options.firstWhere((o) => o.unit.toLowerCase() == 'stück');
      final gramm = options.firstWhere((o) => o.unit.toLowerCase() == 'g');
      expect(stueck.defaultQty, closeTo(0.25, 1e-9),
          reason: 'vorher Bug: 1.0');
      expect(gramm.defaultQty, closeTo(125, 1e-9), reason: 'vorher Bug: 500');
    });

    test('ohne Umrechnungspfad fällt auf Heuristik zurück', () {
      final options = buildDeductUnitOptions(
        inventoryUnit: 'Stück',
        conversions: const [],
        fallbackQty: 1.0,
        diaryMode: true,
        requestedQty: 125,
        requestedUnit: 'g',
      );
      expect(options.single.defaultQty, 1.0);
    });

    test('non-diary Verhalten unverändert (consumeUnit-Default)', () {
      final options = buildDeductUnitOptions(
        inventoryUnit: 'g',
        conversions: [conv('Portion', 'g', 20)],
        consumeQty: 2,
        consumeUnit: 'Portion',
        fallbackQty: 100,
      );
      final portion =
          options.firstWhere((o) => o.unit.toLowerCase() == 'portion');
      expect(portion.defaultQty, 2);
      expect(
          options
              .firstWhere((o) => o.unit.toLowerCase() == 'g')
              .defaultQty,
          100);
    });
  });
}
