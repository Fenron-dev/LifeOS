import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Scans an image for expiry date text and returns the best candidate date.
///
/// Supports common European date formats found on food packaging:
///   dd.mm.yyyy, dd.mm.yy, mm/yyyy, mm.yyyy, dd/mm/yy, "MHD: ...", etc.
class ExpiryDateOcr {
  /// Picks an image from [source] and extracts the most likely expiry date.
  /// Returns null if no recognisable date is found or the user cancels.
  static Future<DateTime?> pickAndRecognize({
    required ImageSource source,
  }) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xfile == null) return null;

    return recognizeFromFile(File(xfile.path));
  }

  /// Runs text recognition on [file] and returns the best expiry date.
  static Future<DateTime?> recognizeFromFile(File file) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(file);
      final recognized = await recognizer.processImage(inputImage);
      return _extractBestDate(recognized.text);
    } finally {
      await recognizer.close();
    }
  }

  static DateTime? _extractBestDate(String text) {
    final now = DateTime.now();
    final candidates = <DateTime>[];

    // Patterns ordered by specificity (most specific first)
    final patterns = [
      // dd.mm.yyyy or dd.mm.yy
      (RegExp(r'\b(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4}|\d{2})\b'), 'dmy'),
      // mm/yyyy or mm.yyyy
      (RegExp(r'\b(\d{1,2})[./](\d{4})\b'), 'my'),
      // yyyy-mm-dd (ISO)
      (RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b'), 'ymd'),
      // "MHD" or "Best before" followed by date
      (RegExp(
          r'(?:MHD|best before|mindestens haltbar|use by)[:\s]+(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4}|\d{2})',
          caseSensitive: false),
       'dmy_prefix'),
    ];

    for (final (pattern, type) in patterns) {
      for (final match in pattern.allMatches(text.replaceAll('\n', ' '))) {
        final dt = _parseMatch(match, type, now.year);
        if (dt != null) candidates.add(dt);
      }
    }

    if (candidates.isEmpty) return null;

    // Filter out clearly invalid dates (in the past > 1 year, or > 10 years future)
    final valid = candidates.where((d) =>
        d.isAfter(now.subtract(const Duration(days: 365))) &&
        d.isBefore(now.add(const Duration(days: 365 * 10)))).toList();

    if (valid.isEmpty) return null;

    // Return the soonest future date (most likely the expiry)
    valid.sort((a, b) => a.compareTo(b));
    return valid.first;
  }

  static DateTime? _parseMatch(RegExpMatch m, String type, int currentYear) {
    try {
      switch (type) {
        case 'dmy':
        case 'dmy_prefix':
          final d = int.parse(m.group(1)!);
          final mo = int.parse(m.group(2)!);
          final y = _expandYear(int.parse(m.group(3)!), currentYear);
          if (!_validDate(d, mo, y)) return null;
          return DateTime(y, mo, d);

        case 'my':
          final mo = int.parse(m.group(1)!);
          final y = int.parse(m.group(2)!);
          if (mo < 1 || mo > 12) return null;
          // End of month
          return DateTime(y, mo + 1, 0);

        case 'ymd':
          final y = int.parse(m.group(1)!);
          final mo = int.parse(m.group(2)!);
          final d = int.parse(m.group(3)!);
          if (!_validDate(d, mo, y)) return null;
          return DateTime(y, mo, d);
      }
    } catch (_) {}
    return null;
  }

  static int _expandYear(int y, int currentYear) {
    if (y >= 100) return y; // already 4-digit
    final century = (currentYear ~/ 100) * 100;
    return y + century;
  }

  static bool _validDate(int d, int m, int y) {
    if (m < 1 || m > 12) return false;
    if (d < 1 || d > 31) return false;
    if (y < 2000 || y > 2040) return false;
    return true;
  }
}
