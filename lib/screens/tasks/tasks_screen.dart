import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/items_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../widgets/adaptive_shell.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _priorityColor(String p, ColorScheme cs) => switch (p) {
      'high' => cs.error,
      'medium' => Colors.orange.shade700,
      _ => cs.outlineVariant,
    };

String _priorityLabel(String p) => switch (p) {
      'high' => 'Hoch',
      'medium' => 'Mittel',
      _ => 'Niedrig',
    };

String _recurrenceLabel(String type, int interval) {
  final n = interval == 1 ? '' : 'alle $interval ';
  return switch (type) {
    'daily' => interval == 1 ? 'Täglich' : 'Alle $interval Tage',
    'weekly' => interval == 1 ? 'Wöchentlich' : 'Alle $interval Wochen',
    'monthly' => interval == 1 ? 'Monatlich' : 'Alle $interval Monate',
    'yearly' => interval == 1 ? 'Jährlich' : 'Alle $interval Jahre',
    _ => '${n}wiederkehrend',
  };
}

bool _isToday(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

bool _isThisWeek(DateTime d) {
  final now = DateTime.now();
  final end = now.add(const Duration(days: 7));
  return d.isAfter(now) && d.isBefore(end);
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TasksScreen extends ConsumerWidget {
  final bool embedded;
  const TasksScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);

    final body = tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (allTasks) {
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

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final overdue = allTasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                t.dueDate!.isBefore(today))
            .toList();
        final todayTasks = allTasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                _isToday(t.dueDate!))
            .toList();
        final thisWeek = allTasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                !_isToday(t.dueDate!) &&
                _isThisWeek(t.dueDate!))
            .toList();
        final later = allTasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                !_isThisWeek(t.dueDate!) &&
                !_isToday(t.dueDate!) &&
                !t.dueDate!.isBefore(today))
            .toList();
        final noDate = allTasks
            .where((t) => t.status != 'done' && t.dueDate == null)
            .toList();
        final done =
            allTasks.where((t) => t.status == 'done').toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (overdue.isNotEmpty) ...[
              _SectionHeader(
                  'Überfällig',
                  Theme.of(context).colorScheme.error,
                  overdue.length),
              ...overdue.map((t) => _TaskTile(task: t)),
            ],
            if (todayTasks.isNotEmpty) ...[
              _SectionHeader('Heute', null, todayTasks.length),
              ...todayTasks.map((t) => _TaskTile(task: t)),
            ],
            if (thisWeek.isNotEmpty) ...[
              _SectionHeader('Diese Woche', null, thisWeek.length),
              ...thisWeek.map((t) => _TaskTile(task: t)),
            ],
            if (later.isNotEmpty) ...[
              _SectionHeader('Später', null, later.length),
              ...later.map((t) => _TaskTile(task: t)),
            ],
            if (noDate.isNotEmpty) ...[
              _SectionHeader('Kein Datum', null, noDate.length),
              ...noDate.map((t) => _TaskTile(task: t)),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SectionHeader('Erledigt', null, done.length),
              ...done.map((t) => _TaskTile(task: t)),
            ],
          ],
        );
      },
    );

    if (embedded) {
      return Stack(
        children: [
          body,
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'add_task',
              onPressed: () => _showDialog(context, ref),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      );
    }

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

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color? color;
  final int count;
  const _SectionHeader(this.label, this.color, this.count);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color ?? theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: (color ?? theme.colorScheme.outline).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: color ?? theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Task tile ─────────────────────────────────────────────────────────────────

class _TaskTile extends ConsumerStatefulWidget {
  final Task task;
  const _TaskTile({required this.task});

  @override
  ConsumerState<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<_TaskTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isDone = task.status == 'done';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final notifier = ref.read(tasksNotifierProvider.notifier);
    final priorityColor = _priorityColor(task.priority, cs);
    final subtasksAsync = ref.watch(subtasksProvider(task.id));
    final subtasks = subtasksAsync.valueOrNull ?? [];
    final allItems = ref.watch(allItemsProvider).valueOrNull ?? [];
    final linkedItem = task.linkedItemId != null
        ? allItems.where((i) => i.id == task.linkedItemId).firstOrNull
        : null;
    final hasSubtasks = subtasks.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Priority bar
                Container(
                  width: 4,
                  color: isDone ? Colors.transparent : priorityColor,
                ),
                Expanded(
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
                              color: cs.outline)
                          : null,
                    ),
                    subtitle: _buildSubtitle(
                        context, linkedItem, subtasks.length),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Expand/collapse toggle — only shown when subtasks exist
                        if (hasSubtasks)
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: IconButton(
                              icon: const Icon(Icons.expand_more, size: 20),
                              onPressed: () =>
                                  setState(() => _expanded = !_expanded),
                              color: cs.outline,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              _showDialog(context);
                            } else if (v == 'add_subtask') {
                              _showDialog(context, parentId: task.id);
                            } else if (v == 'delete') {
                              await notifier.delete(task.id);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_outlined),
                                  SizedBox(width: 8),
                                  Text('Bearbeiten')
                                ])),
                            const PopupMenuItem(
                                value: 'add_subtask',
                                child: Row(children: [
                                  Icon(Icons.subdirectory_arrow_right_outlined),
                                  SizedBox(width: 8),
                                  Text('Unteraufgabe')
                                ])),
                            const PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Löschen',
                                      style: TextStyle(color: Colors.red))
                                ])),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Subtasks (collapsible — auto-expand when first subtask is added)
          if (hasSubtasks && _expanded) ...[
            const Divider(height: 1, indent: 60, endIndent: 16),
            ...subtasks.map((sub) => _SubtaskTile(task: sub)),
            InkWell(
              onTap: () => _showDialog(context, parentId: task.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(60, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 14, color: cs.outline),
                    const SizedBox(width: 4),
                    Text('Unteraufgabe',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.outline)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildSubtitle(
      BuildContext context, Item? linkedItem, int subtaskCount) {
    final task = widget.task;
    final cs = Theme.of(context).colorScheme;
    final isDone = task.status == 'done';
    final now = DateTime.now();
    final isOverdue = task.dueDate != null &&
        task.dueDate!.isBefore(DateTime(now.year, now.month, now.day)) &&
        !isDone;

    final chips = <Widget>[];

    if (task.dueDate != null) {
      chips.add(_SubChip(
        icon: Icons.calendar_today,
        label: DateFormat('dd.MM.yy').format(task.dueDate!),
        color: isOverdue ? cs.error : cs.outline,
      ));
    }

    if (task.priority != 'medium') {
      chips.add(_SubChip(
        icon: task.priority == 'high'
            ? Icons.keyboard_double_arrow_up
            : Icons.keyboard_double_arrow_down,
        label: _priorityLabel(task.priority),
        color: _priorityColor(task.priority, cs),
      ));
    }

    if (task.recurring && task.recurrenceType != null) {
      chips.add(_SubChip(
        icon: Icons.repeat,
        label: _recurrenceLabel(
            task.recurrenceType!, task.recurrenceInterval ?? 1),
        color: cs.outline,
      ));
    }

    if (subtaskCount > 0) {
      chips.add(_SubChip(
        icon: Icons.checklist_outlined,
        label: '$subtaskCount',
        color: cs.primary,
      ));
    }

    if (linkedItem != null) {
      chips.add(GestureDetector(
        onTap: () => context.push('/haushalt/item/${linkedItem.id}'),
        child: _SubChip(
          icon: Icons.inventory_2_outlined,
          label: linkedItem.name,
          color: cs.secondary,
        ),
      ));
    }

    if (task.description != null) {
      chips.add(Text(
        task.description!,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }

    if (chips.isEmpty) return null;
    return Wrap(spacing: 4, runSpacing: 2, children: chips);
  }

  void _showDialog(BuildContext context, {String? parentId}) {
    final task = widget.task;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskDialog(
          task: parentId == null ? task : null, parentId: parentId),
    ).then((_) {
      // Auto-expand when a subtask was just added
      if (parentId != null && mounted) setState(() => _expanded = true);
    });
  }
}

// ── Subtask tile ──────────────────────────────────────────────────────────────

class _SubtaskTile extends ConsumerWidget {
  final Task task;
  const _SubtaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDone = task.status == 'done';
    final cs = Theme.of(context).colorScheme;
    final notifier = ref.read(tasksNotifierProvider.notifier);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 60, right: 8),
      leading: Checkbox(
        value: isDone,
        onChanged: (_) => notifier.toggleDone(task),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      title: Text(
        task.title,
        style: isDone
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: cs.outline,
                fontSize: 13)
            : const TextStyle(fontSize: 13),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 16),
        onPressed: () => notifier.delete(task.id),
        color: cs.outline,
        visualDensity: VisualDensity.compact,
      ),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _TaskDialog(task: task),
      ),
    );
  }
}

class _SubChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SubChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(
          label,
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

// ── Task dialog ───────────────────────────────────────────────────────────────

class _TaskDialog extends ConsumerStatefulWidget {
  final Task? task;
  final String? parentId;
  const _TaskDialog({this.task, this.parentId});

  @override
  ConsumerState<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends ConsumerState<_TaskDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _intervalCtrl;
  DateTime? _dueDate;
  String _priority = 'medium';
  bool _recurring = false;
  String _recurrenceType = 'weekly';
  bool _saving = false;
  String? _linkedItemId;
  String? _linkedItemName;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _notesCtrl = TextEditingController(text: t?.notes ?? '');
    _intervalCtrl = TextEditingController(
        text: (t?.recurrenceInterval ?? 1).toString());
    _dueDate = t?.dueDate;
    _priority = t?.priority ?? 'medium';
    _recurring = t?.recurring ?? false;
    _recurrenceType = t?.recurrenceType ?? 'weekly';
    _linkedItemId = t?.linkedItemId;
    if (_linkedItemId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final allItems = ref.read(allItemsProvider).valueOrNull ?? [];
        final item = allItems.where((i) => i.id == _linkedItemId).firstOrNull;
        if (item != null && mounted) setState(() => _linkedItemName = item.name);
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(tasksNotifierProvider.notifier);
      final interval = int.tryParse(_intervalCtrl.text) ?? 1;
      if (widget.task == null) {
        await notifier.create(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          dueDate: _dueDate,
          priority: _priority,
          recurring: _recurring,
          recurrenceType: _recurring ? _recurrenceType : null,
          recurrenceInterval: _recurring ? interval : null,
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          parentId: widget.parentId,
          linkedItemId: _linkedItemId,
        );
      } else {
        await notifier.save(widget.task!.copyWith(
          title: _titleCtrl.text.trim(),
          description: Value(
              _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
          dueDate: Value(_dueDate),
          priority: _priority,
          recurring: _recurring,
          recurrenceType: Value(_recurring ? _recurrenceType : null),
          recurrenceInterval: Value(_recurring ? interval : null),
          notes: Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
          linkedItemId: Value(_linkedItemId),
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
    final cs = Theme.of(context).colorScheme;
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 24),
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

            // Priority
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Priorität:'),
                ...['low', 'medium', 'high'].map((p) {
                  final selected = _priority == p;
                  final color = _priorityColor(p, cs);
                  return ChoiceChip(
                    label: Text(_priorityLabel(p)),
                    selected: selected,
                    selectedColor: color.withValues(alpha: 0.2),
                    side: BorderSide(
                        color: selected ? color : cs.outlineVariant),
                    labelStyle: TextStyle(
                        color: selected ? color : cs.onSurface),
                    onSelected: (_) =>
                        setState(() => _priority = p),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),

            // Due date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(_dueDate == null
                  ? 'Fälligkeitsdatum (optional)'
                  : 'Fällig: ${DateFormat('dd.MM.yyyy').format(_dueDate!)}'),
              trailing: _dueDate != null
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          setState(() => _dueDate = null),
                    )
                  : null,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now(),
                  firstDate:
                      DateTime.now().subtract(const Duration(days: 365)),
                  lastDate:
                      DateTime.now().add(const Duration(days: 3650)),
                );
                if (d != null) setState(() => _dueDate = d);
              },
            ),

            // Recurring toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.repeat),
              title: const Text('Wiederkehrend'),
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),

            if (_recurring) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Wiederholung',
                          isDense: true),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _recurrenceType,
                          isDense: true,
                          items: const [
                            DropdownMenuItem(
                                value: 'daily',
                                child: Text('Täglich')),
                            DropdownMenuItem(
                                value: 'weekly',
                                child: Text('Wöchentlich')),
                            DropdownMenuItem(
                                value: 'monthly',
                                child: Text('Monatlich')),
                            DropdownMenuItem(
                                value: 'yearly',
                                child: Text('Jährlich')),
                          ],
                          onChanged: (v) =>
                              setState(() => _recurrenceType = v!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _intervalCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Interval'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  () {
                    final n = int.tryParse(_intervalCtrl.text) ?? 1;
                    return _recurrenceLabel(_recurrenceType, n);
                  }(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ),
            ],

            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notiz'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),

            // Item link
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.inventory_2_outlined,
                color: _linkedItemId != null
                    ? Theme.of(context).colorScheme.secondary
                    : null,
              ),
              title: Text(
                _linkedItemName ?? 'Artikel verlinken (optional)',
                style: _linkedItemName != null
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.w500)
                    : null,
              ),
              trailing: _linkedItemId != null
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(
                          () { _linkedItemId = null; _linkedItemName = null; }),
                    )
                  : const Icon(Icons.chevron_right, size: 18),
              onTap: () => _pickItem(context),
            ),

            if (widget.parentId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.subdirectory_arrow_right_outlined,
                        size: 14),
                    const SizedBox(width: 6),
                    Text('Unteraufgabe',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            )),
                  ],
                ),
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
    );
  }

  Future<void> _pickItem(BuildContext context) async {
    final allItems = ref.read(allItemsProvider).valueOrNull ?? [];
    if (allItems.isEmpty) return;
    final picked = await showDialog<Item>(
      context: context,
      builder: (ctx) => _ItemPickerDialog(items: allItems),
    );
    if (picked != null) {
      setState(() {
        _linkedItemId = picked.id;
        _linkedItemName = picked.name;
      });
    }
  }
}

// ── Item picker dialog ────────────────────────────────────────────────────────

class _ItemPickerDialog extends StatefulWidget {
  final List<Item> items;
  const _ItemPickerDialog({required this.items});

  @override
  State<_ItemPickerDialog> createState() => _ItemPickerDialogState();
}

class _ItemPickerDialogState extends State<_ItemPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((i) => i.name.toLowerCase().contains(_query.toLowerCase()) ||
                (i.brand?.toLowerCase().contains(_query.toLowerCase()) ?? false))
            .toList();

    return AlertDialog(
      title: const Text('Artikel wählen'),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Suchen…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
                autofocus: true,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final item = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.inventory_2_outlined, size: 18),
                    title: Text(item.name),
                    subtitle: item.brand != null ? Text(item.brand!) : null,
                    onTap: () => Navigator.of(ctx).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
