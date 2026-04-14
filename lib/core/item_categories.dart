/// Built-in category keys used by [Items.categoryId], [ItemGroups.categoryId],
/// and [TagDefinitions.categoryId]. These are stable string identifiers that
/// double as scope keys for tag definitions (food tags ≠ appliance tags).
///
/// Phase 4 will introduce a `category_definitions` table for user-defined
/// categories; until then these constants are the single source of truth.
/// Never hard-code raw category strings — always use [ItemCategory].
library;

class ItemCategory {
  ItemCategory._();

  /// Groceries, drinks, cooking ingredients.
  static const food = 'food';

  /// Appliances and household goods (electronics, tools, cleaning supplies…).
  static const appliance = 'appliance';

  /// Household tasks and chores.
  static const task = 'task';

  /// Wish-list entries (things to buy/acquire later).
  static const wishlist = 'wishlist';

  /// Recipes — used purely as a tag-definition scope so recipe tags are
  /// separated from item tags. Not used on [Items].
  static const recipe = 'recipe';

  /// All category keys valid for the [Items] `categoryId` column.
  static const allItemCategories = <String>[
    food,
    appliance,
    task,
    wishlist,
  ];

  /// Human-readable German label for a category key. Falls back to the raw
  /// key so unknown/custom category ids still render.
  static String labelDe(String id) {
    switch (id) {
      case food:
        return 'Lebensmittel';
      case appliance:
        return 'Gerät / Haushalt';
      case task:
        return 'Aufgabe';
      case wishlist:
        return 'Wunschliste';
      case recipe:
        return 'Rezept';
      default:
        return id;
    }
  }
}
