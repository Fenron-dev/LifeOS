/// Detects EU-regulated allergens from ingredient text.
///
/// OpenFoodFacts marks allergens with underscores: _Weizen_, _Milch_.
/// This class also does keyword matching for German/English ingredient names.
library;

class AllergenInfo {
  final String id; // e.g. 'gluten'
  final String labelDe;
  final List<String> keywords; // case-insensitive match against ingredient text

  const AllergenInfo({
    required this.id,
    required this.labelDe,
    required this.keywords,
  });
}

class AllergenDetector {
  static const _allergens = [
    AllergenInfo(
      id: 'gluten',
      labelDe: 'Gluten',
      keywords: [
        'weizen', 'dinkel', 'roggen', 'gerste', 'hafer', 'kamut',
        'emmer', 'einkorn', 'wheat', 'rye', 'barley', 'oat', 'spelt',
        'gluten',
      ],
    ),
    AllergenInfo(
      id: 'crustaceans',
      labelDe: 'Krebstiere',
      keywords: [
        'krebstiere', 'garnelen', 'hummer', 'krabben', 'languste',
        'shrimp', 'prawn', 'lobster', 'crab', 'crustacean',
      ],
    ),
    AllergenInfo(
      id: 'eggs',
      labelDe: 'Eier',
      keywords: ['ei', 'eier', 'eigelb', 'eiweiß', 'egg', 'eggs'],
    ),
    AllergenInfo(
      id: 'fish',
      labelDe: 'Fisch',
      keywords: [
        'fisch', 'lachs', 'thunfisch', 'kabeljau', 'dorsch', 'sardine',
        'hering', 'makrele', 'forelle', 'fish', 'salmon', 'tuna',
        'cod', 'anchovy', 'anchovis',
      ],
    ),
    AllergenInfo(
      id: 'peanuts',
      labelDe: 'Erdnüsse',
      keywords: ['erdnuss', 'erdnüsse', 'peanut', 'arachide'],
    ),
    AllergenInfo(
      id: 'soybeans',
      labelDe: 'Soja',
      keywords: ['soja', 'sojaprotein', 'tofu', 'soy', 'soybean'],
    ),
    AllergenInfo(
      id: 'milk',
      labelDe: 'Milch',
      keywords: [
        'milch', 'laktose', 'sahne', 'butter', 'käse', 'quark',
        'joghurt', 'molke', 'casein', 'lactose', 'milk', 'cream',
        'cheese', 'whey', 'dairy',
      ],
    ),
    AllergenInfo(
      id: 'nuts',
      labelDe: 'Schalenfrüchte',
      keywords: [
        'mandel', 'haselnuss', 'walnuss', 'cashew', 'pekan', 'pistazie',
        'paranuss', 'macadamia', 'almond', 'hazelnut', 'walnut',
        'pecan', 'pistachio', 'nut',
      ],
    ),
    AllergenInfo(
      id: 'celery',
      labelDe: 'Sellerie',
      keywords: ['sellerie', 'celery'],
    ),
    AllergenInfo(
      id: 'mustard',
      labelDe: 'Senf',
      keywords: ['senf', 'mustard'],
    ),
    AllergenInfo(
      id: 'sesame',
      labelDe: 'Sesam',
      keywords: ['sesam', 'tahini', 'sesame'],
    ),
    AllergenInfo(
      id: 'sulphites',
      labelDe: 'Sulfite',
      keywords: [
        'schwefeldioxid', 'sulfit', 'sulphite', 'sulfite',
        'e220', 'e221', 'e222', 'e223', 'e224',
      ],
    ),
    AllergenInfo(
      id: 'lupin',
      labelDe: 'Lupinen',
      keywords: ['lupine', 'lupinen', 'lupin'],
    ),
    AllergenInfo(
      id: 'molluscs',
      labelDe: 'Weichtiere',
      keywords: [
        'muschel', 'auster', 'tintenfisch', 'schnecke',
        'mollusc', 'clam', 'oyster', 'squid', 'snail',
      ],
    ),
  ];

  /// Returns allergen IDs detected in [text].
  /// Checks for OFT underscore markers (_word_) first, then keyword scan.
  static List<AllergenInfo> detect(String text) {
    final lower = text.toLowerCase();

    // Extract underscore-marked allergens (OFT format)
    final underscoreTerms = <String>{};
    final underscoreRe = RegExp(r'_([^_]+)_');
    for (final m in underscoreRe.allMatches(lower)) {
      underscoreTerms.add(m.group(1)!);
    }

    final found = <AllergenInfo>[];
    for (final allergen in _allergens) {
      bool detected = false;
      for (final kw in allergen.keywords) {
        // Check underscore-marked terms first
        if (underscoreTerms.any((t) => t.contains(kw))) {
          detected = true;
          break;
        }
        // Then check full text with word-boundary-like matching
        // Use a regex that requires the keyword to be a whole word
        final pattern = RegExp(r'\b' + RegExp.escape(kw) + r'\b');
        if (pattern.hasMatch(lower)) {
          detected = true;
          break;
        }
      }
      if (detected) found.add(allergen);
    }
    return found;
  }

  static AllergenInfo? forId(String id) =>
      _allergens.where((a) => a.id == id).firstOrNull;
}
