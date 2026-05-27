import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../health/widgets/diary_entry_sheet.dart';
import '../health/widgets/food_search_sheet.dart';
import '../l10n/app_localizations.dart';
import '../providers/inventory_provider.dart';
import '../providers/items_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/vault_provider.dart';
import '../screens/items/item_detail_screen.dart';
import '../utils/unit_deduct_utils.dart';

/// Overflow menu actions shared across all main-branch AppBars.
/// Provides navigation to Wishlist and Settings.
List<Widget> shellMenuActions(BuildContext context) => [
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: 'Suchen',
        onPressed: () => context.push('/search'),
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Mehr',
        onSelected: (route) => context.push(route),
        itemBuilder: (_) => const [
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
    label: 'Start',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    route: '/start',
  ),
  const _NavDest(
    label: 'Haushalt',
    icon: Icons.house_outlined,
    selectedIcon: Icons.house,
    route: '/haushalt',
  ),
  const _NavDest(
    label: 'Aufgaben',
    icon: Icons.task_outlined,
    selectedIcon: Icons.task,
    route: '/aufgaben',
  ),
  const _NavDest(
    label: 'Ich',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    route: '/me',
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
    final colorScheme = Theme.of(context).colorScheme;

    final expiringSoon = ref.watch(expiringSoonCountProvider).valueOrNull ?? 0;
    final openTasks = ref.watch(tasksProvider).valueOrNull
            ?.where((t) => t.status != 'done')
            .length ??
        0;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: Row(
          children: [
            _BottomNavItem(
              icon: currentIndex == 0 ? _destinations[0].selectedIcon : _destinations[0].icon,
              label: _destinations[0].label,
              selected: currentIndex == 0,
              onTap: () => onTap(0),
              colorScheme: colorScheme,
            ),
            _BottomNavItem(
              icon: currentIndex == 1 ? _destinations[1].selectedIcon : _destinations[1].icon,
              label: _destinations[1].label,
              selected: currentIndex == 1,
              onTap: () => onTap(1),
              colorScheme: colorScheme,
              badgeCount: expiringSoon,
            ),
            const Spacer(),
            _BottomNavItem(
              icon: currentIndex == 2 ? _destinations[2].selectedIcon : _destinations[2].icon,
              label: _destinations[2].label,
              selected: currentIndex == 2,
              onTap: () => onTap(2),
              colorScheme: colorScheme,
              badgeCount: openTasks,
            ),
            _BottomNavItem(
              icon: currentIndex == 3 ? _destinations[3].selectedIcon : _destinations[3].icon,
              label: _destinations[3].label,
              selected: currentIndex == 3,
              onTap: () => onTap(3),
              colorScheme: colorScheme,
            ),
          ],
        ),
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
      builder: (ctx) => _QuickActionsSheet(
        actions: actions,
        onScanToAdd: () => _handleScan(context, ref),
        onScanToConsume: () => _handleConsumeWithScan(context, ref),
        onQuickDeduct: () => _handleQuickDeduct(context, ref),
        onQuickStock: () => _handleQuickStock(context, ref),
      ),
    );
  }

  Future<void> _handleScan(BuildContext context, WidgetRef ref) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || !context.mounted) return;
    // ean == '' means user tapped "Kein Barcode – manuell eingeben"
    if (ean.isEmpty) {
      context.push('/haushalt/item/new');
      return;
    }
    final dao = ref.read(itemsDaoProvider);
    final existing = await dao?.itemByEan(ean);
    if (!context.mounted) return;
    if (existing != null) {
      context.push('/haushalt/item/${existing.id}');
    } else {
      context.push('/haushalt/item/new', extra: ean);
    }
  }

  Future<void> _handleConsumeWithScan(
      BuildContext context, WidgetRef ref) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || ean.isEmpty || !context.mounted) return;
    final dao = ref.read(itemsDaoProvider);
    final item = await dao?.itemByEan(ean);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Artikel mit diesem Barcode gefunden')),
      );
      return;
    }
    final result =
        await showModalBottomSheet<({Item item, double logicalQty, String unit})?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuickDeductSheet(item: item),
    );
    if (result != null && context.mounted) {
      _offerDiaryEntry(context, result.item, result.logicalQty, result.unit);
    }
  }

  /// Shows a SnackBar offering to log the just-deducted item in the diary.
  void _offerDiaryEntry(
      BuildContext context, Item item, double logicalQty, String unit) {
    final qtyLabel = logicalQty % 1 == 0
        ? logicalQty.toStringAsFixed(0)
        : logicalQty.toStringAsFixed(2);

    double? servingSizeG;
    if (isWeightVolUnit(unit)) {
      servingSizeG = convertWeightVol(logicalQty, unit, 'g') ?? logicalQty;
    } else if (item.servingSizeG != null) {
      servingSizeG = logicalQty * item.servingSizeG!;
    }

    final product = FoodSearchResult(
      productName: item.name,
      brand: item.brand,
      ean: item.ean,
      itemId: item.id,
      caloriesPer100g: item.caloriesPer100g,
      proteinPer100g: item.proteinPer100g,
      carbsPer100g: item.carbsPer100g,
      fatPer100g: item.fatPer100g,
      fiberPer100g: item.fiberPer100g,
      servingSizeG: servingSizeG,
      isRecipe: false,
      nutritionRefUnit: item.nutritionRefUnit,
      source: 'local',
    );

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${item.name}: $qtyLabel $unit ausgebucht'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Im Tagebuch eintragen',
        onPressed: () {
          if (!context.mounted) return;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => DiaryEntrySheet(
              initialProduct: product,
              deductAlreadyDone: true,
            ),
          );
        },
      ),
    ));
  }

  Future<void> _handleQuickDeduct(BuildContext context, WidgetRef ref) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || ean.isEmpty || !context.mounted) return;
    final dao = ref.read(itemsDaoProvider);
    final item = await dao?.itemByEan(ean);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Artikel mit diesem Barcode gefunden')),
      );
      return;
    }

    final db = ref.read(databaseProvider);
    if (db == null || !context.mounted) return;

    final entries = await db.inventoryEntriesForItem(item.id);
    if (!context.mounted) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name}: kein Bestand vorhanden')),
      );
      return;
    }

    final entry = entries.first;
    final invUnit = entry.unit;

    final itemConvs = await db.watchConversionsForItem(item.id).first;
    final globalConvs = await db.watchConversionsGlobal().first;
    final opts = buildDeductUnitOptions(
      inventoryUnit: invUnit,
      conversions: [...itemConvs, ...globalConvs],
      consumeQty: item.consumeQty,
      consumeUnit: item.consumeUnit,
      fallbackQty: 1.0,
    );

    final cu = item.consumeUnit?.toLowerCase().trim();
    final sel = cu != null
        ? opts.firstWhere(
            (o) => o.unit.toLowerCase().trim() == cu,
            orElse: () => opts.first,
          )
        : opts.first;

    final logicalQty = item.consumeQty ?? sel.defaultQty;
    final physicalQty = logicalQty * sel.factor;
    final remaining =
        (entry.quantity - physicalQty).clamp(0.0, double.infinity);

    if (!context.mounted) return;
    await ref.read(inventoryOpsProvider.notifier).consume(
          itemId: item.id,
          inventoryEntryId: entry.id,
          quantity: physicalQty,
          unit: invUnit,
          remainingQuantity: remaining,
          consumptionReason: 'consumed',
        );

    if (context.mounted) {
      _offerDiaryEntry(context, item, logicalQty, sel.unit);
    }
  }

  Future<void> _handleQuickStock(BuildContext context, WidgetRef ref) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || ean.isEmpty || !context.mounted) return;
    final dao = ref.read(itemsDaoProvider);
    final item = await dao?.itemByEan(ean);
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Artikel mit diesem Barcode gefunden')),
      );
      return;
    }
    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddStockSheet(item: item),
    );
    if (booked == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} eingelagert')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Bottom nav item for BottomAppBar
// ---------------------------------------------------------------------------

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final int badgeCount;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: badgeCount > 0,
                label: Text(badgeCount > 9 ? '9+' : '$badgeCount'),
                backgroundColor: colorScheme.error,
                textColor: colorScheme.onError,
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-Actions bottom sheet
// ---------------------------------------------------------------------------

class _QuickActionsSheet extends ConsumerWidget {
  final List<QuickAction> actions;
  final VoidCallback onScanToAdd;
  final VoidCallback onScanToConsume;
  final VoidCallback onQuickDeduct;
  final VoidCallback onQuickStock;
  const _QuickActionsSheet({
    required this.actions,
    required this.onScanToAdd,
    required this.onScanToConsume,
    required this.onQuickDeduct,
    required this.onQuickStock,
  });

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
                title: Text(a.label(AppLocalizations.of(context))),
                onTap: () {
                  Navigator.of(context).pop();
                  if (a == QuickAction.scanBarcode ||
                      a == QuickAction.addInventory) {
                    onScanToAdd();
                  } else if (a == QuickAction.consumeInventory) {
                    onScanToConsume();
                  } else if (a == QuickAction.quickDeduct) {
                    onQuickDeduct();
                  } else if (a == QuickAction.quickStock) {
                    onQuickStock();
                  } else {
                    _navigate(context, a);
                  }
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, QuickAction action) {
    switch (action) {
      case QuickAction.addTask:
        context.push('/aufgaben');
      case QuickAction.addWishlist:
        context.push('/wishlist');
      case QuickAction.addRecipe:
        context.push('/haushalt/recipe/new');
      // scanner-first actions handled before _navigate is called
      case QuickAction.addInventory:
      case QuickAction.consumeInventory:
      case QuickAction.quickDeduct:
      case QuickAction.quickStock:
      case QuickAction.scanBarcode:
        break;
    }
  }
}

// ---------------------------------------------------------------------------
// Tablet: NavigationRail + Content
// ---------------------------------------------------------------------------

class _TabletShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _TabletShell({
    required this.navigationShell,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiringSoon = ref.watch(expiringSoonCountProvider).valueOrNull ?? 0;
    final openTasks = ref.watch(tasksProvider).valueOrNull
            ?.where((t) => t.status != 'done')
            .length ??
        0;
    final badges = [0, expiringSoon, openTasks, 0];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onTap,
            labelType: NavigationRailLabelType.selected,
            destinations: List.generate(_destinations.length, (i) {
              final d = _destinations[i];
              final count = badges[i];
              return NavigationRailDestination(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 9 ? '9+' : '$count'),
                  child: Icon(d.icon),
                ),
                selectedIcon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 9 ? '9+' : '$count'),
                  child: Icon(d.selectedIcon),
                ),
                label: Text(d.label),
              );
            }),
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

class _DesktopShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _DesktopShell({
    required this.navigationShell,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiringSoon = ref.watch(expiringSoonCountProvider).valueOrNull ?? 0;
    final openTasks = ref.watch(tasksProvider).valueOrNull
            ?.where((t) => t.status != 'done')
            .length ??
        0;
    final badges = [0, expiringSoon, openTasks, 0];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onTap,
            extended: true,
            leading: _desktopHeader(context),
            destinations: List.generate(_destinations.length, (i) {
              final d = _destinations[i];
              final count = badges[i];
              return NavigationRailDestination(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 9 ? '9+' : '$count'),
                  child: Icon(d.icon),
                ),
                selectedIcon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 9 ? '9+' : '$count'),
                  child: Icon(d.selectedIcon),
                ),
                label: Text(d.label),
              );
            }),
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

// ---------------------------------------------------------------------------
// Quick-consume picker: search for item → deduct
// ---------------------------------------------------------------------------

class _ConsumePickerSheet extends ConsumerStatefulWidget {
  const _ConsumePickerSheet();

  @override
  ConsumerState<_ConsumePickerSheet> createState() =>
      _ConsumePickerSheetState();
}

class _ConsumePickerSheetState extends ConsumerState<_ConsumePickerSheet> {
  final _searchCtrl = TextEditingController();
  List<Item> _results = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    setState(() => _searching = true);
    final results = query.trim().isEmpty
        ? await db.watchAllItems().first
        : await db.searchItems(query.trim()).first;
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Handle + search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Artikel ausbuchen',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                SearchBar(
                  controller: _searchCtrl,
                  hintText: 'Artikel suchen…',
                  leading: const Icon(Icons.search),
                  onChanged: _search,
                  padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _results.length,
                itemBuilder: (ctx2, i) {
                  final item = _results[i];
                  return ListTile(
                    title: Text(item.name),
                    subtitle: item.brand != null ? Text(item.brand!) : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).pop();
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _QuickDeductSheet(item: item),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-deduct sheet for a single item (no diary log needed)
// ---------------------------------------------------------------------------

typedef _QDUnitOption = UnitDeductOption;

class _QuickDeductSheet extends ConsumerStatefulWidget {
  final Item item;
  const _QuickDeductSheet({required this.item});

  @override
  ConsumerState<_QuickDeductSheet> createState() => _QuickDeductSheetState();
}

class _QuickDeductSheetState extends ConsumerState<_QuickDeductSheet> {
  List<InventoryEntry> _entries = [];
  InventoryEntry? _selected;
  bool _loading = true;
  bool _saving = false;
  late final TextEditingController _qtyCtrl;
  String _reason = 'consumed';

  List<_QDUnitOption> _unitOptions = [];
  _QDUnitOption? _selectedUnit;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '1');
    _loadEntries();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _loadEntries() async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final entries = await db.inventoryEntriesForItem(widget.item.id);
    if (!mounted) return;

    final item = widget.item;
    final inventoryUnit =
        entries.isNotEmpty ? entries.first.unit : (item.consumeUnit ?? 'Stück');

    final itemConvs = await db.watchConversionsForItem(item.id).first;
    final globalConvs = await db.watchConversionsGlobal().first;
    final allConvs = [...itemConvs, ...globalConvs];

    final opts = buildDeductUnitOptions(
      inventoryUnit: inventoryUnit,
      conversions: allConvs,
      consumeQty: item.consumeQty,
      consumeUnit: item.consumeUnit,
      fallbackQty: 1.0,
    );

    // Pre-select consumeUnit option (or first)
    final cu = item.consumeUnit?.toLowerCase().trim();
    final sel = cu != null
        ? opts.firstWhere(
            (o) => o.unit.toLowerCase().trim() == cu,
            orElse: () => opts.first,
          )
        : opts.first;

    InventoryEntry? selectedEntry = entries.isNotEmpty ? entries.first : null;

    setState(() {
      _entries = entries;
      _selected = selectedEntry;
      _unitOptions = opts;
      _selectedUnit = sel;
      _qtyCtrl.text =
          sel.defaultQty % 1 == 0
              ? sel.defaultQty.toStringAsFixed(0)
              : sel.defaultQty.toStringAsFixed(2);
      _loading = false;
    });
  }

  double get _logicalQty =>
      double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;

  double get _physicalQty => _logicalQty * (_selectedUnit?.factor ?? 1.0);

  Future<void> _confirm() async {
    final entry = _selected;
    if (entry == null || _physicalQty <= 0) return;
    setState(() => _saving = true);
    try {
      final remaining =
          (entry.quantity - _physicalQty).clamp(0.0, double.infinity);
      await ref.read(inventoryOpsProvider.notifier).consume(
            itemId: widget.item.id,
            inventoryEntryId: entry.id,
            quantity: _physicalQty,
            unit: entry.unit,
            remainingQuantity: remaining,
            consumptionReason: _reason,
          );
      if (mounted) {
        Navigator.of(context).pop((
          item: widget.item,
          logicalQty: _logicalQty,
          unit: _selectedUnit?.unit ?? entry.unit,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _fmtQty(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _selectUnit(_QDUnitOption opt) {
    setState(() {
      _selectedUnit = opt;
      _qtyCtrl.text = _fmtQty(opt.defaultQty);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    final entry = _selected;
    final invUnit = entry?.unit ?? _selectedUnit?.unit ?? '—';
    final physical = _physicalQty;
    final remaining = entry != null
        ? (entry.quantity - physical).clamp(0.0, double.infinity)
        : 0.0;
    final isRawUnit = _selectedUnit?.unit.toLowerCase() == invUnit.toLowerCase();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(item.name,
                style: Theme.of(context).textTheme.titleMedium),
            if (item.brand != null)
              Text(item.brand!,
                  style:
                      TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_entries.isEmpty)
              Text('Kein Bestand vorhanden.',
                  style: TextStyle(color: cs.onSurfaceVariant))
            else ...[
              // Unit chips (shown when multiple units available)
              if (_unitOptions.length > 1) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _unitOptions.map((opt) {
                    final sel = opt == _selectedUnit;
                    return ChoiceChip(
                      label: Text(opt.unit,
                          style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (_) => _selectUnit(opt),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],

              // Qty field row
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_selectedUnit?.unit ?? invUnit,
                      style:
                          const TextStyle(fontWeight: FontWeight.w500)),
                  if (!isRawUnit) ...[
                    const SizedBox(width: 6),
                    Text('= ${_fmtQty(physical)} $invUnit',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '→ ${_fmtQty(remaining)} $invUnit',
                      style: TextStyle(
                        fontSize: 12,
                        color: remaining <= 0
                            ? cs.error
                            : cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // Entry selector when multiple
              if (_entries.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    children: _entries.map((e) {
                      final sel = _selected?.id == e.id;
                      return ChoiceChip(
                        label: Text(
                          '${_fmtQty(e.quantity)} ${e.unit}'
                          '${e.expiryDate != null ? ' (MHD ${e.expiryDate!.day}.${e.expiryDate!.month}.)' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: sel,
                        onSelected: (_) => setState(() => _selected = e),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'consumed',
                      label: Text('Konsumiert'),
                      icon: Icon(Icons.restaurant, size: 14)),
                  ButtonSegment(
                      value: 'expired',
                      label: Text('Abgelaufen'),
                      icon: Icon(Icons.event_busy, size: 14)),
                  ButtonSegment(
                      value: 'discarded',
                      label: Text('Weggeworfen'),
                      icon: Icon(Icons.delete_outline, size: 14)),
                ],
                selected: {_reason},
                onSelectionChanged: (s) =>
                    setState(() => _reason = s.first),
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_saving ||
                          _loading ||
                          _entries.isEmpty ||
                          _physicalQty <= 0)
                      ? null
                      : _confirm,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Ausbuchen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
