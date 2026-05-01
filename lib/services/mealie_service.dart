import 'dart:convert';
import 'package:http/http.dart' as http;

/// A single imported recipe from Mealie.
class MealieRecipe {
  final String slug;
  final String name;
  final String? description;
  final String? imageUrl;
  final int? prepTime;   // minutes
  final int? cookTime;   // minutes
  final int? servings;
  final String? sourceUrl;
  final List<String> tags;
  final List<MealieIngredient> ingredients;
  final List<String> steps;
  // Nutrition (per serving, if available)
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? fiber;
  final double? sodium;

  const MealieRecipe({
    required this.slug,
    required this.name,
    this.description,
    this.imageUrl,
    this.prepTime,
    this.cookTime,
    this.servings,
    this.sourceUrl,
    this.tags = const [],
    this.ingredients = const [],
    this.steps = const [],
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.fiber,
    this.sodium,
  });
}

class MealieIngredient {
  final String name;
  final double quantity;
  final String unit;
  final bool optional;

  const MealieIngredient({
    required this.name,
    required this.quantity,
    required this.unit,
    this.optional = false,
  });
}

/// Result of inspecting a Mealie base URL for transport security.
enum MealieUrlSecurity {
  /// HTTPS — token is encrypted in transit.
  https,
  /// HTTP, but pointing at a LAN/loopback host. Acceptable for self-hosted
  /// home setups; token leaks only inside the local network.
  httpLocal,
  /// HTTP over a non-LAN host. Token would be sent in clear over the public
  /// internet — show a warning and recommend HTTPS.
  httpRemoteInsecure,
  /// URL could not be parsed at all.
  invalid,
}

class MealieService {
  final String baseUrl;   // e.g. "http://192.168.1.5:9000"
  final String apiToken;  // Mealie API key

  MealieService({required this.baseUrl, required this.apiToken});

  /// Classifies [url] for the connection screen so the UI can warn the user
  /// when their Mealie token would be sent unencrypted over a non-LAN link.
  /// LAN ranges treated as "local": 10/8, 172.16/12, 192.168/16, loopback,
  /// link-local 169.254/16, and any *.local hostname (mDNS).
  static MealieUrlSecurity classifyUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return MealieUrlSecurity.invalid;
    if (uri.scheme == 'https') return MealieUrlSecurity.https;
    if (uri.scheme != 'http') return MealieUrlSecurity.invalid;

    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.local') ||
        host.endsWith('.lan') ||
        host.endsWith('.home.arpa')) {
      return MealieUrlSecurity.httpLocal;
    }
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length == 4 && parts.every((p) => p != null && p >= 0 && p <= 255)) {
      final a = parts[0]!;
      final b = parts[1]!;
      if (a == 127) return MealieUrlSecurity.httpLocal;
      if (a == 10) return MealieUrlSecurity.httpLocal;
      if (a == 192 && b == 168) return MealieUrlSecurity.httpLocal;
      if (a == 172 && b >= 16 && b <= 31) return MealieUrlSecurity.httpLocal;
      if (a == 169 && b == 254) return MealieUrlSecurity.httpLocal;
    }
    return MealieUrlSecurity.httpRemoteInsecure;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      };

  /// Fetch all recipes (summary list).
  Future<List<MealieSummary>> fetchRecipeList({int page = 1, int perPage = 50}) async {
    final uri = Uri.parse('$baseUrl/api/recipes').replace(
      queryParameters: {'page': '$page', 'perPage': '$perPage'},
    );
    final resp = await http.get(uri, headers: _headers);
    _checkStatus(resp);
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => MealieSummary(
              slug: e['slug'] as String,
              name: e['name'] as String,
              imageUrl: _imageUrl(e['slug'] as String),
            ))
        .toList();
  }

  /// Fetch full recipe detail by slug.
  Future<MealieRecipe> fetchRecipe(String slug) async {
    final uri = Uri.parse('$baseUrl/api/recipes/$slug');
    final resp = await http.get(uri, headers: _headers);
    _checkStatus(resp);
    return _parseRecipe(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  String _imageUrl(String slug) =>
      '$baseUrl/api/media/recipes/$slug/images/original.webp';

  MealieRecipe _parseRecipe(Map<String, dynamic> j) {
    final slug = j['slug'] as String;

    // Parse prep/cook times (ISO 8601 duration like "PT30M" or plain minutes)
    int? parseDuration(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      if (s.isEmpty) return null;
      // Try integer first
      final asInt = int.tryParse(s);
      if (asInt != null) return asInt;
      // ISO PT#H#M
      final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?').firstMatch(s);
      if (m != null) {
        final h = int.tryParse(m.group(1) ?? '') ?? 0;
        final min = int.tryParse(m.group(2) ?? '') ?? 0;
        return h * 60 + min;
      }
      return null;
    }

    // Ingredients
    final rawIngs = j['recipeIngredient'] as List<dynamic>? ?? [];
    final ingredients = rawIngs.map((i) {
      final unit =
          (i['unit'] as Map<String, dynamic>?)?['name'] as String? ?? '';
      final qty = (i['quantity'] as num?)?.toDouble() ?? 1.0;
      final food =
          (i['food'] as Map<String, dynamic>?)?['name'] as String? ?? '';
      final note = i['note'] as String? ?? '';
      final name = food.isNotEmpty ? food : note;
      return MealieIngredient(name: name, quantity: qty, unit: unit);
    }).toList();

    // Steps
    final rawSteps = j['recipeInstructions'] as List<dynamic>? ?? [];
    final steps = rawSteps
        .map((s) => (s['text'] as String? ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Tags
    final rawTags = j['tags'] as List<dynamic>? ?? [];
    final tags = rawTags
        .map((t) => (t['name'] as String? ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // Nutrition
    final nut = j['nutrition'] as Map<String, dynamic>?;
    double? parseNut(String key) {
      final v = nut?[key];
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    return MealieRecipe(
      slug: slug,
      name: j['name'] as String? ?? slug,
      description: j['description'] as String?,
      imageUrl: _imageUrl(slug),
      prepTime: parseDuration(j['prepTime']),
      cookTime: parseDuration(j['performTime'] ?? j['cookTime']),
      servings: (j['recipeYield'] as num?)?.toInt(),
      sourceUrl: j['orgURL'] as String?,
      tags: tags,
      ingredients: ingredients,
      steps: steps,
      calories: parseNut('calories'),
      protein: parseNut('proteinContent'),
      carbs: parseNut('carbohydrateContent'),
      fat: parseNut('fatContent'),
      fiber: parseNut('fiberContent'),
      sodium: parseNut('sodiumContent'),
    );
  }

  void _checkStatus(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          'Mealie-Fehler ${resp.statusCode}: ${resp.reasonPhrase}');
    }
  }
}

class MealieSummary {
  final String slug;
  final String name;
  final String? imageUrl;
  const MealieSummary(
      {required this.slug, required this.name, this.imageUrl});
}
