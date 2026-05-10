/// Built-in category keys used by [Items.categoryId], [ItemGroups.categoryId],
/// and [TagDefinitions.categoryId]. These are stable string identifiers that
/// double as scope keys for tag definitions (food tags ≠ appliance tags).
///
/// Phase 4 will introduce a `category_definitions` table for user-defined
/// categories; until then these constants are the single source of truth.
/// Never hard-code raw category strings — always use [ItemCategory].
library;

import 'package:flutter/material.dart';

class ItemCategory {
  ItemCategory._();

  /// Groceries, drinks, cooking ingredients.
  static const food = 'food';

  /// Electronics, tools, household appliances.
  static const appliance = 'appliance';

  /// Accessories and spare parts for appliances/devices.
  static const equipment = 'equipment';

  /// Consumables: cleaning supplies, batteries, paper products, etc.
  static const consumable = 'consumable';

  /// Personal care & hygiene products.
  static const personalCare = 'personal_care';

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
    equipment,
    consumable,
    personalCare,
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
      case equipment:
        return 'Zubehör / Ersatzteile';
      case consumable:
        return 'Verbrauchsmaterial';
      case personalCare:
        return 'Körperpflege';
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

  /// Material icon for a built-in category.
  static IconData iconFor(String id) {
    switch (id) {
      case food:
        return Icons.local_grocery_store_outlined;
      case appliance:
        return Icons.devices_outlined;
      case equipment:
        return Icons.handyman_outlined;
      case consumable:
        return Icons.cleaning_services_outlined;
      case personalCare:
        return Icons.spa_outlined;
      case task:
        return Icons.task_outlined;
      case wishlist:
        return Icons.star_outline;
      case recipe:
        return Icons.menu_book_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}
