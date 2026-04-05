import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/groups_provider.dart';
import '../../providers/items_provider.dart';
import '../../providers/unit_conversions_provider.dart';
import '../../providers/vault_provider.dart';
import '../settings/unit_conversions_screen.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(allGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Produktgruppen')),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (groups) {
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('Noch keine Gruppen'),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Gruppen fassen Artikel zusammen und definieren Mindestbestände für die Einkaufsliste.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Gruppe anlegen'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: groups.length,
            itemBuilder: (context, i) => _GroupCard(group: groups[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, ref),
        tooltip: 'Gruppe anlegen',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref, [ItemGroup? group]) {
    showDialog(
      context: context,
      builder: (_) => _GroupDialog(group: group),
    );
  }
}

// ── Group card ────────────────────────────────────────────────────────────────

class _GroupCard extends ConsumerWidget {
  final ItemGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.category_outlined)),
        title: Text(group.name),
        subtitle: group.minStockQuantity != null
            ? Text(
                'Mindestbestand: ${_fmt(group.minStockQuantity!)} ${group.minStockUnit ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : const Text('Kein Mindestbestand',
                style: TextStyle(color: Colors.grey)),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              _showEdit(context, ref);
            } else if (v == 'delete') {
              await ref.read(groupsNotifierProvider.notifier).delete(group.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 8),
                  Text('Bearbeiten')
                ])),
            PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Löschen', style: TextStyle(color: Colors.red))
                ])),
          ],
        ),
        children: [
          _MembersSection(group: group),
          _GroupConversionsSection(group: group),
        ],
      ),
    );
  }

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  void _showEdit(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (_) => _GroupDialog(group: group));
  }
}

// ── Group conversions section ─────────────────────────────────────────────────

class _GroupConversionsSection extends ConsumerWidget {
  final ItemGroup group;
  const _GroupConversionsSection({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convsAsync = ref.watch(groupConversionsProvider(group.id));
    return convsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (convs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ConversionsList(
          conversions: convs,
          onAdd: () => showAddConversionDialog(
            context,
            onSave: (from, to, factor) => ref
                .read(conversionsNotifierProvider.notifier)
                .addForGroup(
                  groupId: group.id,
                  fromUnit: from,
                  toUnit: to,
                  factor: factor,
                ),
          ),
        ),
      ),
    );
  }
}

// ── Members section ───────────────────────────────────────────────────────────

class _MembersSection extends ConsumerWidget {
  final ItemGroup group;
  const _MembersSection({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    if (db == null) return const SizedBox.shrink();

    return FutureBuilder(
      future: db.membersForGroup(group.id),
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Artikel (${members.length})',
                      style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showMemberPicker(context, ref, members),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Artikel hinzufügen'),
                  ),
                ],
              ),
              if (members.isEmpty)
                const Text('Noch keine Artikel in dieser Gruppe.',
                    style: TextStyle(color: Colors.grey))
              else
                ...members.map((m) => _MemberTile(
                      groupId: group.id,
                      itemId: m.itemId,
                    )),
            ],
          ),
        );
      },
    );
  }

  void _showMemberPicker(
      BuildContext context, WidgetRef ref, List<ItemGroupMember> current) {
    final currentIds = current.map((m) => m.itemId).toSet();
    showDialog(
      context: context,
      builder: (_) => _MemberPickerDialog(
        groupId: group.id,
        currentMemberIds: currentIds,
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  final String groupId;
  final String itemId;
  const _MemberTile({required this.groupId, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemByIdProvider(itemId));
    return itemAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, st) => const SizedBox.shrink(),
      data: (item) {
        if (item == null) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(item.name),
          subtitle:
              item.brand != null ? Text(item.brand!) : null,
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            tooltip: 'Aus Gruppe entfernen',
            onPressed: () => ref
                .read(groupsNotifierProvider.notifier)
                .removeMember(groupId, itemId),
          ),
        );
      },
    );
  }
}

// ── Member picker dialog ──────────────────────────────────────────────────────

class _MemberPickerDialog extends ConsumerWidget {
  final String groupId;
  final Set<String> currentMemberIds;
  const _MemberPickerDialog(
      {required this.groupId, required this.currentMemberIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(allItemsProvider);
    return AlertDialog(
      title: const Text('Artikel auswählen'),
      content: SizedBox(
        width: double.maxFinite,
        child: itemsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Fehler: $e'),
          data: (items) => ListView.builder(
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final isMember = currentMemberIds.contains(item.id);
              return CheckboxListTile(
                title: Text(item.name),
                subtitle: item.brand != null ? Text(item.brand!) : null,
                value: isMember,
                onChanged: (checked) {
                  final notifier =
                      ref.read(groupsNotifierProvider.notifier);
                  if (checked == true) {
                    notifier.addMember(groupId, item.id);
                  } else {
                    notifier.removeMember(groupId, item.id);
                  }
                },
              );
            },
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fertig'),
        ),
      ],
    );
  }
}

// ── Group dialog ──────────────────────────────────────────────────────────────

class _GroupDialog extends ConsumerStatefulWidget {
  final ItemGroup? group;
  const _GroupDialog({this.group});

  @override
  ConsumerState<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends ConsumerState<_GroupDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _minQtyCtrl;
  String _minUnit = 'Stück';
  bool _saving = false;

  static const _units = [
    'Stück', 'g', 'kg', 'ml', 'l', 'Packung',
  ];

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _minQtyCtrl = TextEditingController(
        text: g?.minStockQuantity != null
            ? _fmt(g!.minStockQuantity!)
            : '');
    _minUnit = g?.minStockUnit ?? 'Stück';
  }

  String _fmt(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _minQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final notifier = ref.read(groupsNotifierProvider.notifier);
    final minQty = double.tryParse(_minQtyCtrl.text.replaceAll(',', '.'));
    try {
      if (widget.group == null) {
        await notifier.create(
          name: _nameCtrl.text.trim(),
          minStockQuantity: minQty,
          minStockUnit: minQty != null ? _minUnit : null,
        );
      } else {
        await notifier.save(
          id: widget.group!.id,
          name: _nameCtrl.text.trim(),
          categoryId: widget.group!.categoryId,
          minStockQuantity: minQty,
          minStockUnit: minQty != null ? _minUnit : null,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.group == null ? 'Gruppe anlegen' : 'Gruppe bearbeiten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name *'),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Mindestbestand (optional)',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _minQtyCtrl,
                decoration: const InputDecoration(labelText: 'Menge'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _minUnit,
                decoration: const InputDecoration(labelText: 'Einheit'),
                items: _units
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) => setState(() => _minUnit = v!),
              ),
            ),
          ]),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}
