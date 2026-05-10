import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/tasks_provider.dart';
import '../../widgets/adaptive_shell.dart';

class TasksScreen extends ConsumerWidget {
  /// When true, omits the Scaffold/AppBar — used when embedded in a TabBarView.
  final bool embedded;
  const TasksScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);

    final body = tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (allTasks) {
        final pending = allTasks.where((t) => t.status != 'done').toList();
        final done = allTasks.where((t) => t.status == 'done').toList();

        if (allTasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.task_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                const Text('Keine Aufgaben'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _showDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Aufgabe anlegen'),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            ...pending.map((t) => _TaskTile(task: t)),
            if (done.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Erledigt',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 4),
              ...done.map((t) => _TaskTile(task: t)),
            ],
          ],
        );
      },
    );

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgaben'),
        actions: shellMenuActions(context),
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref, [Task? task]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskDialog(task: task),
    );
  }
}

// ── Task tile ─────────────────────────────────────────────────────────────────

class _TaskTile extends ConsumerWidget {
  final Task task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDone = task.status == 'done';
    final theme = Theme.of(context);
    final notifier = ref.read(tasksNotifierProvider.notifier);
    final isOverdue = task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now()) &&
        !isDone;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Checkbox(
          value: isDone,
          onChanged: (_) => notifier.toggleDone(task),
        ),
        title: Text(
          task.title,
          style: isDone
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline)
              : null,
        ),
        subtitle: _buildSubtitle(context, isOverdue),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              _showEdit(context, ref);
            } else if (v == 'delete') {
              await notifier.delete(task.id);
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

  Widget? _buildSubtitle(BuildContext context, bool isOverdue) {
    final parts = <InlineSpan>[];
    if (task.dueDate != null) {
      parts.add(TextSpan(
        text: 'Fällig: ${DateFormat('dd.MM.yy').format(task.dueDate!)}',
        style: TextStyle(
            color: isOverdue
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurfaceVariant),
      ));
    }
    if (task.description != null) {
      if (parts.isNotEmpty) parts.add(const TextSpan(text: '  '));
      parts.add(TextSpan(
          text: task.description!,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }
    if (parts.isEmpty) return null;
    return Text.rich(
      TextSpan(children: parts),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _showEdit(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskDialog(task: task),
    );
  }
}

// ── Task dialog ───────────────────────────────────────────────────────────────

class _TaskDialog extends ConsumerStatefulWidget {
  final Task? task;
  const _TaskDialog({this.task});

  @override
  ConsumerState<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends ConsumerState<_TaskDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _notesCtrl;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _notesCtrl = TextEditingController(text: t?.notes ?? '');
    _dueDate = t?.dueDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(tasksNotifierProvider.notifier);
      if (widget.task == null) {
        await notifier.create(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          dueDate: _dueDate,
          notes:
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await notifier.save(widget.task!.copyWith(
          title: _titleCtrl.text.trim(),
          description: Value(
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
          dueDate: Value(_dueDate),
          notes: Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
          updatedAt: DateTime.now(),
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
            widget.task == null ? 'Neue Aufgabe' : 'Aufgabe bearbeiten',
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
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: 'Beschreibung'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text(_dueDate == null
                ? 'Fälligkeitsdatum (optional)'
                : 'Fällig: ${DateFormat('dd.MM.yyyy').format(_dueDate!)}'),
            trailing: _dueDate != null
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dueDate = null),
                  )
                : null,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _dueDate ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (d != null) setState(() => _dueDate = d);
            },
          ),
          const SizedBox(height: 8),
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
