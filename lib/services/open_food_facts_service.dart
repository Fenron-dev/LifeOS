import 'dart:convert';
import 'package:http/http.dart' as http;

/// Product data fetched from OpenFoodFacts.
class OFFProduct {
  final String ean;
  final String name;
  final String? brand;
  final String? imageUrl;
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;

  const OFFProduct({
    required this.ean,
    required this.name,
    this.brand,
    this.imageUrl,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
  });
}

class OpenFoodFactsService {
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';
  static const _userAgent = 'LifeOS/1.0 (github.com/fenron/lifeos)';

  /// Looks up a product by EAN barcode. Returns null if not found.
  static Future<OFFProduct?> lookup(String ean) async {
    try {
      final uri = Uri.parse('$_baseUrl/$ean.json'
          '?fields=product_name,brands,image_url,nutriments');
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['status'] != 1) return null;

      final product = body['product'] as Map<String, dynamic>;
      final nutriments =
          product['nutriments'] as Map<String, dynamic>? ?? {};

      return OFFProduct(
        ean: ean,
        name: (product['product_name'] as String? ?? '').trim(),
        brand: (product['brands'] as String? ?? '').trim().isNotEmpty
            ? (product['brands'] as String).trim()
            : null,
        imageUrl: product['image_url'] as String?,
        calories: _toDouble(nutriments['energy-kcal_100g']),
        protein: _toDouble(nutriments['proteins_100g']),
        carbs: _toDouble(nutriments['carbohydrates_100g']),
        fat: _toDouble(nutriments['fat_100g']),
      );
    } catch (_) {
      return null;
    }
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
