import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/shops_provider.dart';

class ShopsScreen extends ConsumerWidget {
  const ShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopsAsync = ref.watch(allShopsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Geschäfte')),
      body: shopsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (shops) {
          if (shops.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.store_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('Noch keine Geschäfte'),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Füge Geschäfte hinzu, um sie beim Einlagern schnell auswählen zu können.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Geschäft hinzufügen'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: shops.length,
            itemBuilder: (context, i) => _ShopTile(shop: shops[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, ref),
        tooltip: 'Geschäft hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref, [Shop? shop]) {
    showDialog(
      context: context,
      builder: (_) => _ShopDialog(shop: shop),
    );
  }
}

class _ShopTile extends ConsumerWidget {
  final Shop shop;
  const _ShopTile({required this.shop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.store_outlined)),
        title: Text(shop.name),
        subtitle: shop.notes != null ? Text(shop.notes!) : null,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              _showEdit(context, ref);
            } else if (v == 'delete') {
              await ref.read(shopsNotifierProvider.notifier).delete(shop.id);
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
      ),
    );
  }

  void _showEdit(BuildContext context, WidgetRef ref) {
    showDialog(
        context: context, builder: (_) => _ShopDialog(shop: shop));
  }
}

class _ShopDialog extends ConsumerStatefulWidget {
  final Shop? shop;
  const _ShopDialog({this.shop});

  @override
  ConsumerState<_ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends ConsumerState<_ShopDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.shop?.name ?? '');
    _notesCtrl = TextEditingController(text: widget.shop?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final notifier = ref.read(shopsNotifierProvider.notifier);
    try {
      if (widget.shop == null) {
        await notifier.create(
          _nameCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await notifier.save(widget.shop!.copyWith(
          name: _nameCtrl.text.trim(),
          notes: Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
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
          widget.shop == null ? 'Geschäft hinzufügen' : 'Geschäft bearbeiten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name *'),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notiz (optional)'),
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
