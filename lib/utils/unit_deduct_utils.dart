import '../db/database.dart';

/// One selectable deduction unit.
/// [factor] = how many inventory-native units equal 1 logical unit.
/// E.g. if inventory is "g" and logical unit is "Portion" (20g): factor = 20.
class UnitDeductOption {
  final String unit;
  final double factor; // 1 logical = factor * inventory
  final double defaultQty;
  const UnitDeductOption(this.unit, this.factor, this.defaultQty);

  @override
  bool operator ==(Object other) =>
      other is UnitDeductOption &&
      other.unit.toLowerCase() == unit.toLowerCase();

  @override
  int get hashCode => unit.toLowerCase().hashCode;
}

bool isWeightVolUnit(String unit) {
  switch (unit.toLowerCase().trim()) {
    case 'g':
    case 'gr':
    case 'gramm':
    case 'mg':
    case 'kg':
    case 'kilogramm':
    case 'ml':
    case 'milliliter':
    case 'cl':
    case 'dl':
    case 'l':
    case 'liter':
      return true;
    default:
      return false;
  }
}

double? convertWeightVol(double qty, String from, String to) {
  final f = from.toLowerCase().trim();
  final t = to.toLowerCase().trim();
  if (f == t) return qty;
  if (f == 'g' && (t == 'kg' || t == 'kilogramm')) return qty / 1000;
  if ((f == 'kg' || f == 'kilogramm') && t == 'g') return qty * 1000;
  if (f == 'ml' && (t == 'l' || t == 'liter')) return qty / 1000;
  if ((f == 'l' || f == 'liter') && t == 'ml') return qty * 1000;
  if (f == 'cl' && t == 'ml') return qty * 10;
  if (f == 'ml' && t == 'cl') return qty / 10;
  if (f == 'dl' && t == 'ml') return qty * 100;
  if (f == 'ml' && t == 'dl') return qty / 100;
  return null;
}

/// Returns F such that 1 [logicalUnit] = F [inventoryUnit].
/// [logicalToUnit] + [logicalFactor] define: 1 logicalUnit = logicalFactor * logicalToUnit.
double? factorToInventory({
  required String logicalToUnit,
  required double logicalFactor,
  required String inventoryUnit,
  required List<UnitConversion> allConversions,
}) {
  final toLo = logicalToUnit.toLowerCase().trim();
  final invLo = inventoryUnit.toLowerCase().trim();

  if (toLo == invLo) return logicalFactor;

  if (isWeightVolUnit(toLo) && isWeightVolUnit(invLo)) {
    final w = convertWeightVol(logicalFactor, logicalToUnit, inventoryUnit);
    if (w != null) return w;
  }

  for (final c2 in allConversions) {
    final c2f = c2.fromUnit.toLowerCase().trim();
    final c2t = c2.toUnit.toLowerCase().trim();
    if (c2f == toLo && c2t == invLo) return logicalFactor * c2.factor;
    if (c2t == toLo && c2f == invLo && c2.factor > 0) {
      return logicalFactor / c2.factor;
    }
    if (c2f == toLo && isWeightVolUnit(c2t) && isWeightVolUnit(invLo)) {
      final w =
          convertWeightVol(logicalFactor * c2.factor, c2.toUnit, inventoryUnit);
      if (w != null) return w;
    }
  }

  return null;
}

/// Returns the gram weight of 1 [unit] given [conversions].
/// Returns null if no gram-equivalent is found.
double? unitToGrams(String unit, List<UnitConversion> conversions) {
  final uLo = unit.toLowerCase().trim();
  if (uLo == 'g' || uLo == 'gr' || uLo == 'gramm') return 1.0;
  if (uLo == 'kg' || uLo == 'kilogramm') return 1000.0;
  if (uLo == 'ml' || uLo == 'milliliter') return 1.0;
  if (uLo == 'cl') return 10.0;
  if (uLo == 'dl') return 100.0;
  if (uLo == 'l' || uLo == 'liter') return 1000.0;

  for (final c in conversions) {
    if (c.fromUnit.toLowerCase().trim() == uLo) {
      final to = c.toUnit.toLowerCase().trim();
      if (to == 'g' || to == 'gramm' || to == 'gr') return c.factor;
      if (to == 'kg' || to == 'kilogramm') return c.factor * 1000;
      if (to == 'ml' || to == 'milliliter') return c.factor;
      if (to == 'cl') return c.factor * 10;
      if (to == 'dl') return c.factor * 100;
      if (to == 'l' || to == 'liter') return c.factor * 1000;
    }
    // Reverse: g → unit (1 unit = 1/factor g)
    if (c.toUnit.toLowerCase().trim() == uLo && c.factor > 0) {
      final from = c.fromUnit.toLowerCase().trim();
      if (from == 'g' || from == 'gramm' || from == 'gr') {
        return 1.0 / c.factor;
      }
      if (from == 'kg' || from == 'kilogramm') return 1000.0 / c.factor;
    }
  }
  return null;
}

/// Builds the list of selectable deduction unit options.
/// Always includes the raw [inventoryUnit] (factor = 1).
List<UnitDeductOption> buildDeductUnitOptions({
  required String inventoryUnit,
  required List<UnitConversion> conversions,
  double? consumeQty,
  String? consumeUnit,
  required double fallbackQty,
}) {
  final invLo = inventoryUnit.toLowerCase().trim();
  final options = <UnitDeductOption>[];
  final seen = <String>{invLo};

  double defQtyFor(String u) {
    if (consumeUnit?.toLowerCase().trim() == u.toLowerCase().trim()) {
      return consumeQty ?? 1.0;
    }
    return u.toLowerCase().trim() == invLo ? fallbackQty : 1.0;
  }

  options.add(UnitDeductOption(inventoryUnit, 1.0, defQtyFor(inventoryUnit)));

  for (final conv in conversions) {
    final fromLo = conv.fromUnit.toLowerCase().trim();
    final toLo = conv.toUnit.toLowerCase().trim();

    if (!seen.contains(fromLo)) {
      final f = factorToInventory(
        logicalToUnit: conv.toUnit,
        logicalFactor: conv.factor,
        inventoryUnit: inventoryUnit,
        allConversions: conversions,
      );
      if (f != null) {
        options.add(
            UnitDeductOption(conv.fromUnit, f, defQtyFor(conv.fromUnit)));
        seen.add(fromLo);
      }
    }

    if (!seen.contains(toLo) && conv.factor > 0) {
      final f = factorToInventory(
        logicalToUnit: conv.fromUnit,
        logicalFactor: 1.0 / conv.factor,
        inventoryUnit: inventoryUnit,
        allConversions: conversions,
      );
      if (f != null) {
        options
            .add(UnitDeductOption(conv.toUnit, f, defQtyFor(conv.toUnit)));
        seen.add(toLo);
      }
    }
  }

  return options;
}
