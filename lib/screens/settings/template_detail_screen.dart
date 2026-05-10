import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/templates_provider.dart';

const _fieldTypes = [
  ('text', 'Text', Icons.text_fields),
  ('number', 'Zahl', Icons.numbers),
  ('date', 'Datum', Icons.calendar_today_outlined),
  ('boolean', 'Ja / Nein', Icons.toggle_on_outlined),
  ('tags', 'Tags', Icons.label_outline),
  ('liste', 'Liste', Icons.list),
  ('link', 'Link', Icons.link),
];

String _fieldTypeLabel(String type) =>
    _fieldTypes.firstWhere((t) => t.$1 == type, orElse: () => (type, type, Icons.help_outline)).$2;

IconData _fieldTypeIcon(String type) =>
    _fieldTypes.firstWhere((t) => t.$1 == type, orElse: () => (type, type, Icons.help_outline)).$3;

class TemplateDetailScreen extends ConsumerWidget {
  final String templateId;
  const TemplateDetailScreen({super.key, required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(templateFieldsProvider(templateId));
    final templatesAsync = ref.watch(allTemplatesProvider);
    final template = templatesAsync.valueOrNull
        ?.where((t) => t.id == templateId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(template?.name ?? 'Template'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Feld hinzufügen',
            onPressed: () => _showFieldDialog(context, ref, null),
          ),
        ],
      ),
      body: fieldsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (fields) {
          if (fields.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  const Text('Noch keine Felder.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showFieldDialog(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Feld hinzufügen'),
                  ),
                ],
              ),
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: fields.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex -= 1;
              final reordered = List.of(fields);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              final updates = reordered
                  .asMap()
                  .entries
                  .map((e) => (id: e.value.id, sortOrder: e.key))
                  .toList();
              await ref
                  .read(templatesNotifierProvider.notifier)
                  .reorderFields(updates);
            },
            itemBuilder: (context, i) {
              final field = fields[i];
              return ListTile(
                key: ValueKey(field.id),
                leading: Icon(_fieldTypeIcon(field.fieldType)),
                title: Text(field.fieldName),
                subtitle: Text(_fieldTypeLabel(field.fieldType) +
                    (field.required ? ' · Pflichtfeld' : '')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          _showFieldDialog(context, ref, field),
                    ),
                    if (template?.isBuiltIn != true)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => ref
                            .read(templatesNotifierProvider.notifier)
                            .deleteField(field.id),
                      ),
                    const Icon(Icons.drag_handle),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showFieldDialog(
      BuildContext context, WidgetRef ref, TemplateField? existing) {
    showDialog(
      context: context,
      builder: (_) => _FieldDialog(templateId: templateId, existing: existing),
    );
  }
}

class _FieldDialog extends ConsumerStatefulWidget {
  final String templateId;
  final TemplateField? existing;
  const _FieldDialog({required this.templateId, this.existing});

  @override
  ConsumerState<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends ConsumerState<_FieldDialog> {
  late final TextEditingController _nameCtrl;
  late String _type;
  late bool _required;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.fieldName ?? '');
    _type = widget.existing?.fieldType ?? 'text';
    _required = widget.existing?.required ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Feld hinzufügen' : 'Feld bearbeiten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Feldname *'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _type,
            decoration: const InputDecoration(labelText: 'Feldtyp'),
            items: _fieldTypes
                .map((t) => DropdownMenuItem(
                      value: t.$1,
                      child: Row(
                        children: [
                          Icon(t.$3, size: 18),
                          const SizedBox(width: 8),
                          Text(t.$2),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _required,
            onChanged: (v) => setState(() => _required = v ?? false),
            title: const Text('Pflichtfeld'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
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
            if (widget.existing == null) {
              final currentFields = await ref
                  .read(templateFieldsProvider(widget.templateId).future);
              await notifier.addField(
                templateId: widget.templateId,
                fieldName: name,
                fieldType: _type,
                required: _required,
                sortOrder: currentFields.length,
              );
            } else {
              await notifier.updateField(
                id: widget.existing!.id,
                templateId: widget.templateId,
                fieldName: name,
                fieldType: _type,
                required: _required,
                sortOrder: widget.existing!.sortOrder,
              );
            }
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
