import 'dart:convert';
import 'package:http/http.dart' as http;

/// All importable fields from OpenFoodFacts.
enum OFFField {
  name,
  brand,
  calories,
  protein,
  carbs,
  fat,
  fiber,
  sugars,
  saturatedFat,
  salt,
  servingSize,
  nutriscore,
  novaGroup,
  ingredientsText,
}

/// Product data fetched from OpenFoodFacts.
class OFFProduct {
  final String ean;
  final String? name;
  final String? brand;
  final String? imageUrl;
  // Nutrition per 100g
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? fiber;
  final double? sugars;
  final double? saturatedFat;
  final double? salt;
  final double? servingSizeG;
  final String? nutriscore; // a/b/c/d/e
  final int? novaGroup;    // 1–4
  final String? ingredientsText;

  const OFFProduct({
    required this.ean,
    this.name,
    this.brand,
    this.imageUrl,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.fiber,
    this.sugars,
    this.saturatedFat,
    this.salt,
    this.servingSizeG,
    this.nutriscore,
    this.novaGroup,
    this.ingredientsText,
  });

  /// Returns true if [field] has a non-null value.
  bool hasField(OFFField field) {
    return switch (field) {
      OFFField.name => name != null && name!.isNotEmpty,
      OFFField.brand => brand != null && brand!.isNotEmpty,
      OFFField.calories => calories != null,
      OFFField.protein => protein != null,
      OFFField.carbs => carbs != null,
      OFFField.fat => fat != null,
      OFFField.fiber => fiber != null,
      OFFField.sugars => sugars != null,
      OFFField.saturatedFat => saturatedFat != null,
      OFFField.salt => salt != null,
      OFFField.servingSize => servingSizeG != null,
      OFFField.nutriscore => nutriscore != null,
      OFFField.novaGroup => novaGroup != null,
      OFFField.ingredientsText =>
        ingredientsText != null && ingredientsText!.isNotEmpty,
    };
  }
}

class _LookupCacheEntry {
  final OFFProduct? value;
  final DateTime fetchedAt;
  _LookupCacheEntry(this.value, this.fetchedAt);
}

class OpenFoodFactsService {
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';
  static const _userAgent = 'LifeOS/1.0 (github.com/fenron/lifeos)';

  static const _fields =
      'product_name,brands,image_url,nutriments,nutriscore_grade,'
      'nova_group,ingredients_text,serving_size';

  // OFF asks clients to cache and not hammer their API. We keep an in-process
  // cache keyed by EAN (24 h for hits, 10 min for misses) plus an in-flight
  // map that deduplicates parallel requests for the same code.
  static const _cacheMaxEntries = 200;
  static const _hitTtl = Duration(hours: 24);
  static const _missTtl = Duration(minutes: 10);
  static final Map<String, _LookupCacheEntry> _lookupCache = {};
  static final Map<String, Future<OFFProduct?>> _inflight = {};

  /// Test/debug helper — clears the lookup cache.
  static void clearCache() {
    _lookupCache.clear();
    _inflight.clear();
  }

  /// Looks up a product by EAN barcode. Returns null if not found.
  static Future<OFFProduct?> lookup(String ean) async {
    final cached = _lookupCache[ean];
    if (cached != null) {
      final age = DateTime.now().difference(cached.fetchedAt);
      final ttl = cached.value == null ? _missTtl : _hitTtl;
      if (age < ttl) {
        // Touch for LRU.
        _lookupCache.remove(ean);
        _lookupCache[ean] = cached;
        return cached.value;
      }
      _lookupCache.remove(ean);
    }

    final inflight = _inflight[ean];
    if (inflight != null) return inflight;

    final future = _fetchAndCache(ean);
    _inflight[ean] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(ean);
    }
  }

  static Future<OFFProduct?> _fetchAndCache(String ean) async {
    final result = await _fetchFromApi(ean);
    _lookupCache[ean] = _LookupCacheEntry(result, DateTime.now());
    if (_lookupCache.length > _cacheMaxEntries) {
      // Evict oldest insertion (Map preserves insertion order in Dart).
      _lookupCache.remove(_lookupCache.keys.first);
    }
    return result;
  }

  static Future<OFFProduct?> _fetchFromApi(String ean) async {
    try {
      final uri = Uri.parse('$_baseUrl/$ean.json?fields=$_fields');
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['status'] != 1) return null;

      final product = body['product'] as Map<String, dynamic>;
      final nutriments =
          product['nutriments'] as Map<String, dynamic>? ?? {};

      final name = (product['product_name'] as String? ?? '').trim();
      final brand = (product['brands'] as String? ?? '').trim();

      // Parse serving size (e.g. "30 g" → 30.0)
      final servingRaw = product['serving_size'] as String?;
      final servingSizeG = _parseServingSize(servingRaw);

      return OFFProduct(
        ean: ean,
        name: name.isNotEmpty ? name : null,
        brand: brand.isNotEmpty ? brand : null,
        imageUrl: product['image_url'] as String?,
        calories: _toDouble(nutriments['energy-kcal_100g']),
        protein: _toDouble(nutriments['proteins_100g']),
        carbs: _toDouble(nutriments['carbohydrates_100g']),
        fat: _toDouble(nutriments['fat_100g']),
        fiber: _toDouble(nutriments['fiber_100g']),
        sugars: _toDouble(nutriments['sugars_100g']),
        saturatedFat: _toDouble(nutriments['saturated-fat_100g']),
        salt: _toDouble(nutriments['salt_100g']),
        servingSizeG: servingSizeG,
        nutriscore:
            (product['nutriscore_grade'] as String?)?.toLowerCase().trim(),
        novaGroup: _toInt(product['nova_group']),
        ingredientsText:
            (product['ingredients_text'] as String?)?.trim().isNotEmpty == true
                ? (product['ingredients_text'] as String).trim()
                : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Searches products by name. Returns up to [pageSize] results.
  static Future<List<OFFProduct>> searchByName(
    String query, {
    int pageSize = 15,
  }) async {
    try {
      final uri = Uri.parse(
        'https://world.openfoodfacts.org/cgi/search.pl',
      ).replace(queryParameters: {
        'search_terms': query,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '$pageSize',
        'fields': 'code,product_name,brands,image_url,nutriments,'
            'nutriscore_grade,nova_group,ingredients_text,serving_size',
      });

      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final products = body['products'] as List<dynamic>? ?? [];

      return products
          .map((p) => _parseProduct(p as Map<String, dynamic>))
          .whereType<OFFProduct>()
          .where((p) =>
              p.name != null &&
              p.name!.isNotEmpty &&
              p.name!.toLowerCase() != 'unknown')
          .toList();
    } catch (_) {
      return [];
    }
  }

  static OFFProduct? _parseProduct(Map<String, dynamic> product) {
    final code = (product['code'] as String? ?? '').trim();
    if (code.isEmpty) return null;

    final nutriments = product['nutriments'] as Map<String, dynamic>? ?? {};
    final name = (product['product_name'] as String? ?? '').trim();
    final brand = (product['brands'] as String? ?? '').trim();
    final servingSizeG = _parseServingSize(product['serving_size'] as String?);

    return OFFProduct(
      ean: code,
      name: name.isNotEmpty ? name : null,
      brand: brand.isNotEmpty ? brand : null,
      imageUrl: product['image_url'] as String?,
      calories: _toDouble(nutriments['energy-kcal_100g']),
      protein: _toDouble(nutriments['proteins_100g']),
      carbs: _toDouble(nutriments['carbohydrates_100g']),
      fat: _toDouble(nutriments['fat_100g']),
      fiber: _toDouble(nutriments['fiber_100g']),
      sugars: _toDouble(nutriments['sugars_100g']),
      saturatedFat: _toDouble(nutriments['saturated-fat_100g']),
      salt: _toDouble(nutriments['salt_100g']),
      servingSizeG: servingSizeG,
      nutriscore:
          (product['nutriscore_grade'] as String?)?.toLowerCase().trim(),
      novaGroup: _toInt(product['nova_group']),
      ingredientsText:
          (product['ingredients_text'] as String?)?.trim().isNotEmpty == true
              ? (product['ingredients_text'] as String).trim()
              : null,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Parses "30 g", "30g", "30ml" → grams as double (ml≈g for water-like).
  static double? _parseServingSize(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(raw);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }
}
