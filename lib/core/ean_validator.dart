/// Barcode/EAN validation shared by the item form and the scanners (#3).
///
/// Accepts EAN-8 (8 digits), UPC-A (12 digits), EAN-13 (13 digits) with
/// checksum, or any other all-digit code of 6–20 characters (internal
/// barcodes, ITF-14, …). Checksums are only enforced where they exist
/// (8/13 digits) — a failed checksum almost always means a camera misread.
library;

/// Returns a human-readable error, or null when [value] is acceptable.
/// Empty input is acceptable (the EAN field is optional).
String? validateEanMessage(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final code = value.trim();
  if (!RegExp(r'^\d+$').hasMatch(code)) return 'Nur Ziffern erlaubt';
  if (code.length < 6 || code.length > 20) {
    return 'Ungültige Länge (6–20 Stellen)';
  }
  if (code.length == 8 || code.length == 13) {
    int sum = 0;
    for (int i = 0; i < code.length - 1; i++) {
      final d = int.parse(code[i]);
      sum += (code.length == 13)
          ? (i.isEven ? d : d * 3)
          : (i.isEven ? d * 3 : d);
    }
    final check = (10 - (sum % 10)) % 10;
    if (check != int.parse(code[code.length - 1])) {
      return 'Ungültige Prüfziffer';
    }
  }
  return null;
}

/// True when a scanned code should be accepted by the barcode scanners.
bool isAcceptableEan(String code) =>
    code.trim().isNotEmpty && validateEanMessage(code) == null;
