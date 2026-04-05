import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/settings_provider.dart';

/// Overflow menu actions shared across all main-branch AppBars.
/// Provides navigation to Wishlist and Settings.
List<Widget> shellMenuActions(BuildContext context) => [
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Mehr',
        onSelected: (route) => context.push(route),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: '/wishlist',
            child: Row(children: [
              Icon(Icons.star_outline),
              SizedBox(width: 12),
              Text('Wunschliste'),
            ]),
          ),
          PopupMenuItem(
            value: '/settings',
            child: Row(children: [
              Icon(Icons.settings_outlined),
              SizedBox(width: 12),
              Text('Einstellungen'),
            ]),
          ),
        ],
      ),
    ];

// Breakpoints
const _kMobileBreakpoint = 600.0;
const _kDesktopBreakpoint = 1200.0;

/// Navigation destination descriptor
class _NavDest {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;

  const _NavDest({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
  });
}

// ignore: prefer_function_declarations_over_variables
final _destinations = [
  const _NavDest(
    label: 'Inventar',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    route: '/inventory',
  ),
  const _NavDest(
    label: 'Rezepte',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
    route: '/recipes',
  ),
  const _NavDest(
    label: 'Aufgaben',
    icon: Icons.task_outlined,
    selectedIcon: Icons.task,
    route: '/tasks',
  ),
];

class AdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AdaptiveShell({super.key, required this.navigationShell});

  int get _currentIndex => navigationShell.currentIndex;

  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= _kDesktopBreakpoint) {
      return _DesktopShell(
        navigationShell: navigationShell,
        currentIndex: _currentIndex,
        onTap: (i) => _onTap(context, i),
      );
    } else if (width >= _kMobileBreakpoint) {
      return _TabletShell(
        navigationShell: navigationShell,
        currentIndex: _currentIndex,
        onTap: (i) => _onTap(context, i),
      );
    } else {
      return _MobileShell(
        navigationShell: navigationShell,
        currentIndex: _currentIndex,
        onTap: (i) => _onTap(context, i),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Mobile: Bottom NavigationBar
// ---------------------------------------------------------------------------

class _MobileShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _MobileShell({
    required this.navigationShell,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final actions = settings?.quickActions ?? AppSettingsData.defaultQuickActions;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        destinations: _destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ))
            .toList(),
      ),
      floatingActionButton: actions.isEmpty
          ? null
          : FloatingActionButton(
              heroTag: 'quick_action',
              onPressed: () => _showQuickActions(context, ref, actions),
              tooltip: 'Schnellaktionen',
              child: const Icon(Icons.add),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  void _showQuickActions(
      BuildContext context, WidgetRef ref, List<QuickAction> actions) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _QuickActionsSheet(actions: actions),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-Actions bottom sheet
// ---------------------------------------------------------------------------

class _QuickActionsSheet extends ConsumerWidget {
  final List<QuickAction> actions;
  const _QuickActionsSheet({required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Schnellaktionen',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/settings');
                  },
                  child: const Text('Konfigurieren'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...actions.map((a) => ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(a.icon,
                      color:
                          Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                title: Text(a.label),
                onTap: () {
                  Navigator.of(context).pop();
                  _navigate(context, a);
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, QuickAction action) {
    switch (action) {
      case QuickAction.addInventory:
        context.push('/inventory/item/new');
      case QuickAction.consumeInventory:
        context.push('/inventory');
      case QuickAction.addTask:
        context.push('/tasks');
      case QuickAction.addWishlist:
        context.push('/wishlist');
      case QuickAction.addRecipe:
        context.push('/recipes/new');
    }
  }
}

// ---------------------------------------------------------------------------
// Tablet: NavigationRail + Content
// ---------------------------------------------------------------------------

class _TabletShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _TabletShell({
    required this.navigationShell,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onTap,
            labelType: NavigationRailLabelType.selected,
            destinations: _destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop: Extended NavigationRail (3-panel handled inside each screen)
// ---------------------------------------------------------------------------

class _DesktopShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _DesktopShell({
    required this.navigationShell,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onTap,
            extended: true,
            leading: _desktopHeader(context),
            destinations: _destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }

  Widget _desktopHeader(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Column(
          children: [
            const Icon(Icons.home, size: 32),
            const SizedBox(height: 4),
            Text(
              'LifeOS',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      );
}
