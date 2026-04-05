import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/units_provider.dart';

class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitsAsync = ref.watch(allUnitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einheiten')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Standard-Einheiten sind vorbelegt und können umbenannt, aber nicht gelöscht werden.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: unitsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (units) => ReorderableListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: units.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex--;
                  final notifier =
                      ref.read(unitsNotifierProvider.notifier);
                  // Reassign sortOrder for all affected units
                  final reordered = [...units];
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, moved);
                  for (var i = 0; i < reordered.length; i++) {
                    await notifier.save(reordered[i].copyWith(
                      sortOrder: i,
                    ));
                  }
                },
                itemBuilder: (context, i) {
                  final unit = units[i];
                  return Card(
                    key: ValueKey(unit.id),
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle),
                      title: Text(unit.name),
                      subtitle: unit.abbreviation != null
                          ? Text('Abkürzung: ${unit.abbreviation}')
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Bearbeiten',
                            onPressed: () => _showDialog(
                                context, ref, unit),
                          ),
                          if (!unit.isDefault)
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: 'Löschen',
                              onPressed: () => ref
                                  .read(unitsNotifierProvider.notifier)
                                  .delete(unit.id),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, ref),
        tooltip: 'Einheit hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref, [Unit? unit]) {
    showDialog(
      context: context,
      builder: (_) => _UnitDialog(unit: unit),
    );
  }
}

class _UnitDialog extends ConsumerStatefulWidget {
  final Unit? unit;
  const _UnitDialog({this.unit});

  @override
  ConsumerState<_UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends ConsumerState<_UnitDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _abbrCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.unit?.name ?? '');
    _abbrCtrl =
        TextEditingController(text: widget.unit?.abbreviation ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _abbrCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final notifier = ref.read(unitsNotifierProvider.notifier);
    try {
      if (widget.unit == null) {
        await notifier.create(
          _nameCtrl.text.trim(),
          abbreviation: _abbrCtrl.text.trim().isEmpty
              ? null
              : _abbrCtrl.text.trim(),
        );
      } else {
        await notifier.save(widget.unit!.copyWith(
          name: _nameCtrl.text.trim(),
          abbreviation: Value(_abbrCtrl.text.trim().isEmpty
              ? null
              : _abbrCtrl.text.trim()),
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.unit == null ? 'Einheit hinzufügen' : 'Einheit bearbeiten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Name *', hintText: 'z. B. Packung'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _abbrCtrl,
            decoration: const InputDecoration(
                labelText: 'Abkürzung (optional)',
                hintText: 'z. B. Pkg.'),
          ),
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
