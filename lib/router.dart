import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/vault_provider.dart';
import 'screens/vault/vault_selection_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/items/item_detail_screen.dart';
import 'screens/items/item_form_screen.dart';
import 'screens/scanner/barcode_scanner_screen.dart';
import 'screens/recipes/recipes_screen.dart';
import 'screens/recipes/recipe_detail_screen.dart';
import 'screens/recipes/recipe_form_screen.dart';
import 'screens/recipes/mealie_import_screen.dart';
import 'screens/recipes/meals_screen.dart';
import 'screens/tasks/tasks_screen.dart';
import 'screens/wishlist/wishlist_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/shops_screen.dart';
import 'screens/settings/unit_conversions_screen.dart';
import 'screens/settings/units_screen.dart';
import 'screens/settings/meal_types_screen.dart';
import 'screens/settings/help_screen.dart';
import 'screens/locations/locations_screen.dart';
import 'screens/inventory/groups_screen.dart';
import 'screens/inventory/shopping_list_screen.dart';
import 'screens/inventory/shelf_life_screen.dart';
import 'health/screens/me_screen.dart';
import 'widgets/adaptive_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final vaultPath = ref.watch(vaultPathProvider);

  return GoRouter(
    initialLocation: '/inventory',
    redirect: (context, state) {
      if (vaultPath == null && state.matchedLocation != '/vault') return '/vault';
      if (vaultPath != null && state.matchedLocation == '/vault') return '/inventory';
      return null;
    },
    routes: [
      GoRoute(
        path: '/vault',
        builder: (context, state) => const VaultSelectionScreen(),
      ),

      // Full-screen barcode scanner (accessible from anywhere)
      GoRoute(
        path: '/scan',
        builder: (context, state) => const BarcodeScannerScreen(),
      ),

      // ── Wishlist & Settings: full-screen push routes (not in shell nav) ──
      GoRoute(
        path: '/wishlist',
        builder: (context, state) => const WishlistScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'locations',
            builder: (context, state) => const LocationsScreen(),
          ),
          GoRoute(
            path: 'shops',
            builder: (context, state) => const ShopsScreen(),
          ),
          GoRoute(
            path: 'unit-conversions',
            builder: (context, state) => const UnitConversionsScreen(),
          ),
          GoRoute(
            path: 'units',
            builder: (context, state) => const UnitsScreen(),
          ),
          GoRoute(
            path: 'meal-types',
            builder: (context, state) => const MealTypesScreen(),
          ),
          GoRoute(
            path: 'help',
            builder: (context, state) => const HelpScreen(),
          ),
        ],
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveShell(navigationShell: shell),
        branches: [
          // ── Inventory branch ─────────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inventory',
                builder: (context, state) => const InventoryScreen(),
                routes: [
                  GoRoute(
                    path: 'item/new',
                    builder: (context, state) => ItemFormScreen(
                      prefillEan: state.extra as String?,
                    ),
                  ),
                  GoRoute(
                    path: 'item/:id',
                    builder: (context, state) => ItemDetailScreen(
                      itemId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => ItemFormScreen(
                          itemId: state.pathParameters['id'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'shopping',
                    builder: (context, state) => const ShoppingListScreen(),
                  ),
                  GoRoute(
                    path: 'groups',
                    builder: (context, state) => const GroupsScreen(),
                  ),
                  GoRoute(
                    path: 'shelf-life',
                    builder: (context, state) => const ShelfLifeScreen(),
                  ),
                ],
              ),
            ],
          ),
          // ── Recipes branch ────────────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/recipes',
                builder: (context, state) => const RecipesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const RecipeFormScreen(),
                  ),
                  GoRoute(
                    path: 'import',
                    builder: (context, state) => const MealieImportScreen(),
                  ),
                  GoRoute(
                    path: 'meals',
                    builder: (context, state) => const MealsScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => RecipeDetailScreen(
                      recipeId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => RecipeFormScreen(
                          recipeId: state.pathParameters['id'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // ── Tasks branch ──────────────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          // ── "Ich" / Health branch (replaces former /stats) ───────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/me',
                builder: (context, state) => const MeScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
