import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../providers/inventory_provider.dart';
import '../providers/items_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vault_provider.dart';

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
            ),
            const Spacer(),
            _BottomNavItem(
              icon: currentIndex == 2 ? _destinations[2].selectedIcon : _destinations[2].icon,
              label: _destinations[2].label,
              selected: currentIndex == 2,
              onTap: () => onTap(2),
              colorScheme: colorScheme,
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
        onScanRequest: () => _handleScan(context, ref),
      ),
    );
  }

  Future<void> _handleScan(BuildContext context, WidgetRef ref) async {
    final ean = await context.push<String>('/scan');
    if (ean == null || !context.mounted) return;
    final dao = ref.read(itemsDaoProvider);
    final existing = await dao?.itemByEan(ean);
    if (!context.mounted) return;
    if (existing != null) {
      context.push('/inventory/item/${existing.id}');
    } else {
      context.push('/inventory/item/new', extra: ean);
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

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
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
              Icon(icon, color: color, size: 24),
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
  final VoidCallback onScanRequest;
  const _QuickActionsSheet({required this.actions, required this.onScanRequest});

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
                  if (a == QuickAction.scanBarcode) {
                    onScanRequest();
                  } else if (a == QuickAction.consumeInventory) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => const _ConsumePickerSheet(),
                    );
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
      case QuickAction.scanBarcode:
        context.push('/scan');
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

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final preQty = item.consumeQty ?? 1.0;
    _qtyCtrl = TextEditingController(
        text: preQty % 1 == 0
            ? preQty.toStringAsFixed(0)
            : preQty.toStringAsFixed(2));
    _loadEntries();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final db = ref.read(databaseProvider);
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final entries = await db.inventoryEntriesForItem(widget.item.id);
    if (!mounted) return;
    InventoryEntry? sel = entries.isNotEmpty ? entries.first : null;
    // If item has a consumeUnit, prefer an entry matching that unit
    final cu = widget.item.consumeUnit;
    if (cu != null && entries.isNotEmpty) {
      sel = entries.firstWhere(
        (e) => e.unit.toLowerCase() == cu.toLowerCase(),
        orElse: () => entries.first,
      );
    }
    setState(() {
      _entries = entries;
      _selected = sel;
      _loading = false;
    });
  }

  double get _deductQty =>
      double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;

  Future<void> _confirm() async {
    final entry = _selected;
    if (entry == null || _deductQty <= 0) return;
    setState(() => _saving = true);
    try {
      final remaining =
          (entry.quantity - _deductQty).clamp(0.0, double.infinity);
      await ref.read(inventoryOpsProvider.notifier).consume(
            itemId: widget.item.id,
            inventoryEntryId: entry.id,
            quantity: _deductQty,
            unit: entry.unit,
            remainingQuantity: remaining,
            consumptionReason: _reason,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _fmtQty(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    final entry = _selected;
    final unit = entry?.unit ?? item.consumeUnit ?? '—';
    final remaining = entry != null
        ? (entry.quantity - _deductQty).clamp(0.0, double.infinity)
        : 0.0;

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
            Text(item.name, style: Theme.of(context).textTheme.titleMedium),
            if (item.brand != null)
              Text(item.brand!,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_entries.isEmpty)
              Text('Kein Bestand vorhanden.',
                  style: TextStyle(color: cs.onSurfaceVariant))
            else ...[
              // Qty row
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
                        fillColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(unit,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 16),
                  Text(
                    '→ verbleibend: ${_fmtQty(remaining)} $unit',
                    style: TextStyle(
                      fontSize: 12,
                      color: remaining <= 0 ? cs.error : cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
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
              // Reason selector
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
                          _deductQty <= 0)
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
