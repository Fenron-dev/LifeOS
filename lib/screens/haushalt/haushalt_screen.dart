import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/groups_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/recipes_provider.dart';
import '../../providers/wishlist_provider.dart';
import '../../widgets/adaptive_shell.dart';

class HaushaltScreen extends ConsumerWidget {
  const HaushaltScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Haushalt'),
        actions: shellMenuActions(context),
      ),
      body: const _HaushaltGrid(),
    );
  }
}

class _HaushaltGrid extends ConsumerWidget {
  const _HaushaltGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiringCount = ref.watch(expiringCountProvider).valueOrNull ?? 0;
    final totalItems = ref.watch(allItemsProvider).valueOrNull?.length ?? 0;
    final itemsWithStock =
        ref.watch(itemsWithStockProvider).valueOrNull?.length ?? 0;
    final groups = ref.watch(allGroupsProvider).valueOrNull?.length ?? 0;
    final recipes = ref.watch(allRecipesProvider).valueOrNull?.length ?? 0;
    final meals = ref.watch(allMealsProvider).valueOrNull?.length ?? 0;
    final wishlistCount = ref.watch(wishlistProvider).valueOrNull?.length ?? 0;

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 900 ? 3 : 2;

    final cards = [
      _CardData(
        title: 'Haltbarkeiten',
        icon: Icons.event_busy_outlined,
        route: '/haushalt/shelf-life',
        stat: expiringCount > 0 ? '$expiringCount ablaufend' : 'Alle frisch',
        statHighlight: expiringCount > 0,
      ),
      _CardData(
        title: 'Inventar',
        icon: Icons.inventory_2_outlined,
        route: '/haushalt/inventory',
        stat: '$itemsWithStock mit Bestand',
      ),
      _CardData(
        title: 'Produkte',
        icon: Icons.category_outlined,
        route: '/haushalt/products',
        stat: '$totalItems gesamt',
      ),
      _CardData(
        title: 'Gruppen',
        icon: Icons.folder_outlined,
        route: '/haushalt/groups',
        stat: '$groups Gruppen',
      ),
      _CardData(
        title: 'Gerichte',
        icon: Icons.restaurant_outlined,
        route: '/haushalt/meals',
        stat: '$meals Gerichte',
      ),
      _CardData(
        title: 'Rezepte',
        icon: Icons.menu_book_outlined,
        route: '/haushalt/recipes',
        stat: '$recipes Rezepte',
      ),
      _CardData(
        title: 'Menüplan',
        icon: Icons.calendar_month_outlined,
        route: '/haushalt/plan',
        stat: '',
      ),
      _CardData(
        title: 'Wunschliste',
        icon: Icons.star_outline,
        route: '/wishlist',
        stat: wishlistCount > 0 ? '$wishlistCount Wünsche' : 'Leer',
      ),
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemCount: cards.length,
      itemBuilder: (context, i) => _HaushaltCard(data: cards[i]),
    );
  }
}

class _CardData {
  final String title;
  final IconData icon;
  final String route;
  final String stat;
  final bool statHighlight;

  const _CardData({
    required this.title,
    required this.icon,
    required this.route,
    this.stat = '',
    this.statHighlight = false,
  });
}

class _HaushaltCard extends StatelessWidget {
  final _CardData data;
  const _HaushaltCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statColor =
        data.statHighlight ? cs.error : cs.onSurfaceVariant;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(data.route),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(data.icon, size: 32, color: cs.primary),
              const SizedBox(height: 12),
              Text(
                data.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (data.stat.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  data.stat,
                  style: TextStyle(fontSize: 12, color: statColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
