import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/vault_provider.dart';
import 'screens/vault/vault_selection_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/items/item_detail_screen.dart';
import 'screens/items/item_form_screen.dart';
import 'screens/scanner/barcode_scanner_screen.dart';
import 'screens/recipes/recipes_screen.dart';
import 'screens/tasks/tasks_screen.dart';
import 'screens/wishlist/wishlist_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/locations/locations_screen.dart';
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
          // ── Wishlist branch ───────────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wishlist',
                builder: (context, state) => const WishlistScreen(),
              ),
            ],
          ),
          // ── Settings branch ───────────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'locations',
                    builder: (context, state) => const LocationsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
