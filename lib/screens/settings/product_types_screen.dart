import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../db/database.dart';
import '../../providers/product_types_provider.dart';

class ProductTypesScreen extends ConsumerWidget {
  const ProductTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(allProductTypesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produkttypen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neuer Produkttyp',
            onPressed: () => _showDialog(context, ref, null),
          ),
        ],
      ),
      body: typesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (types) => ListView.builder(
          itemCount: types.length,
          itemBuilder: (context, i) {
            final t = types[i];
            return ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(t.nameDe),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.isBuiltIn)
                    Chip(
                      label: const Text('Standard',
                          style: TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  if (!t.isBuiltIn) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _showDialog(context, ref, t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _confirmDelete(context, ref, t),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showDialog(
      BuildContext context, WidgetRef ref, ProductTypeDefinition? existing) {
    showDialog(
      context: context,
      builder: (_) => _ProductTypeDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      ProductTypeDefinition t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Produkttyp löschen?'),
        content: Text('„${t.nameDe}" wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(productTypesNotifierProvider.notifier).delete(t.id);
    }
  }
}

class _ProductTypeDialog extends ConsumerStatefulWidget {
  final ProductTypeDefinition? existing;
  const _ProductTypeDialog({this.existing});

  @override
  ConsumerState<_ProductTypeDialog> createState() =>
      _ProductTypeDialogState();
}

class _ProductTypeDialogState extends ConsumerState<_ProductTypeDialog> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.nameDe ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Neuer Produkttyp'
          : 'Produkttyp bearbeiten'),
      content: TextField(
        controller: _nameCtrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name *'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () async {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final notifier =
                ref.read(productTypesNotifierProvider.notifier);
            // Use name as id (lowercase, spaces → underscores)
            final id = widget.existing?.id ??
                name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
            if (widget.existing == null) {
              await notifier.create(id: id, nameDe: name);
            } else {
              await notifier.save(id: id, nameDe: name);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
