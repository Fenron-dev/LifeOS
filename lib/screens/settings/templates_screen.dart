import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/templates_provider.dart';

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(allTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neues Template',
            onPressed: () => _showTemplateDialog(context, ref, null),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (templates) {
          if (templates.isEmpty) {
            return const Center(
              child: Text('Noch keine Templates.\nTippe + um eines zu erstellen.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: templates.length,
            itemBuilder: (context, i) {
              final tpl = templates[i];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(tpl.name),
                subtitle: tpl.description != null ? Text(tpl.description!) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tpl.isBuiltIn)
                      Chip(
                        label: const Text('Standard', style: TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          context.push('/settings/templates/${tpl.id}'),
                    ),
                    if (!tpl.isBuiltIn)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _confirmDelete(context, ref, tpl),
                      ),
                  ],
                ),
                onTap: () => context.push('/settings/templates/${tpl.id}'),
              );
            },
          );
        },
      ),
    );
  }

  void _showTemplateDialog(
      BuildContext context, WidgetRef ref, ItemTemplate? existing) {
    showDialog(
      context: context,
      builder: (_) => _TemplateDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ItemTemplate tpl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Template löschen?'),
        content: Text('„${tpl.name}" wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => ctx.pop(true),
              child:
                  const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(templatesNotifierProvider.notifier).deleteTemplate(tpl.id);
    }
  }
}

class _TemplateDialog extends ConsumerStatefulWidget {
  final ItemTemplate? existing;
  const _TemplateDialog({this.existing});

  @override
  ConsumerState<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends ConsumerState<_TemplateDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl =
        TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.existing == null ? 'Neues Template' : 'Template bearbeiten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration:
                const InputDecoration(labelText: 'Beschreibung (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () async {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final notifier = ref.read(templatesNotifierProvider.notifier);
            final desc = _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim();
            if (widget.existing == null) {
              await notifier.createTemplate(name: name, description: desc);
            } else {
              await notifier.updateTemplate(
                  id: widget.existing!.id, name: name, description: desc);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
