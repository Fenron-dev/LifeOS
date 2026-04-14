import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/wishlist_provider.dart';
import '../../widgets/adaptive_shell.dart';

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(wishlistProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wunschliste'),
        actions: shellMenuActions(context),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('Noch nichts auf der Wunschliste'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Wunsch hinzufügen'),
                  ),
                ],
              ),
            );
          }

          final open = entries.where((e) => !e.fulfilled).toList();
          final done = entries.where((e) => e.fulfilled).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (open.isNotEmpty) ...[
                ...open.map((e) => _WishCard(entry: e)),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Erfüllt',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 4),
                ...done.map((e) => _WishCard(entry: e)),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref, [WishListEntry? entry]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WishDialog(entry: entry),
    );
  }
}

// ── Wish card ────────────────────────────────────────────────────────────────

class _WishCard extends ConsumerWidget {
  final WishListEntry entry;
  const _WishCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(wishlistNotifierProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: entry.fulfilled,
          onChanged: (_) => notifier.toggleFulfilled(entry),
        ),
        title: Text(
          entry.title,
          style: entry.fulfilled
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline)
              : null,
        ),
        subtitle: _subtitle(context),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PriorityChip(priority: entry.priority),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  _showEdit(context, ref);
                } else if (v == 'delete') {
                  await notifier.delete(entry.id);
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
          ],
        ),
      ),
    );
  }

  Widget? _subtitle(BuildContext context) {
    final parts = <String>[];
    if (entry.price != null) parts.add('${entry.price!.toStringAsFixed(2)} €');
    if (entry.forPerson != null) parts.add('für ${entry.forPerson}');
    if (entry.url != null) parts.add(entry.url!);
    if (entry.notes != null) parts.add(entry.notes!);
    if (parts.isEmpty) return null;
    return Text(parts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall);
  }

  void _showEdit(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WishDialog(entry: entry),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String priority;
  const _PriorityChip({required this.priority});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (priority) {
      'high' => ('Hoch', Colors.red),
      'low' => ('Niedrig', Colors.grey),
      _ => ('Mittel', Colors.orange),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

// ── Wish dialog ───────────────────────────────────────────────────────────────

class _WishDialog extends ConsumerStatefulWidget {
  final WishListEntry? entry;
  const _WishDialog({this.entry});

  @override
  ConsumerState<_WishDialog> createState() => _WishDialogState();
}

class _WishDialogState extends ConsumerState<_WishDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _personCtrl;
  late final TextEditingController _notesCtrl;
  String _priority = 'medium';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _priceCtrl = TextEditingController(
        text: e?.price != null ? e!.price!.toStringAsFixed(2) : '');
    _personCtrl = TextEditingController(text: e?.forPerson ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _priority = e?.priority ?? 'medium';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _priceCtrl.dispose();
    _personCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(wishlistNotifierProvider.notifier);
      final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.'));
      if (widget.entry == null) {
        await notifier.create(
          title: _titleCtrl.text.trim(),
          url: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
          price: price,
          priority: _priority,
          forPerson:
              _personCtrl.text.trim().isEmpty ? null : _personCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await notifier.save(widget.entry!.copyWith(
          title: _titleCtrl.text.trim(),
          url: Value(_urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim()),
          price: Value(price),
          priority: _priority,
          forPerson: Value(_personCtrl.text.trim().isEmpty
              ? null
              : _personCtrl.text.trim()),
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
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.entry == null ? 'Neuer Wunsch' : 'Wunsch bearbeiten',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Titel *'),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          // Priority selector
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'low', label: Text('Niedrig')),
              ButtonSegment(value: 'medium', label: Text('Mittel')),
              ButtonSegment(value: 'high', label: Text('Hoch')),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _priceCtrl,
                decoration: const InputDecoration(
                    labelText: 'Preis (€)', prefixIcon: Icon(Icons.euro)),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _personCtrl,
                decoration: const InputDecoration(
                    labelText: 'Für wen?',
                    prefixIcon: Icon(Icons.person_outline)),
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
                labelText: 'URL (optional)', prefixIcon: Icon(Icons.link)),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notiz'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}
