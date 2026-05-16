import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../../providers/items_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../widgets/adaptive_shell.dart';
import '../../widgets/entity_photo_section.dart';
import '../../widgets/search_filter_bar.dart';

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

/// Opens the add/edit task bottom-sheet. Can be called from outside this file.
Future<void> showAddTaskSheet(BuildContext context,
        {Task? task, String? parentId}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskDialog(task: task, parentId: parentId),
    );

class TasksScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const TasksScreen({super.key, this.embedded = false});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _query = '';
  String? _priorityFilter; // 'low' | 'medium' | 'high'
  String? _statusFilter;   // 'open' | 'done' | 'overdue'
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasFilters => _priorityFilter != null || _statusFilter != null;

  List<Task> _applyFilters(List<Task> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var tasks = all;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      tasks = tasks.where((t) => t.title.toLowerCase().contains(q)).toList();
    }
    if (_priorityFilter != null) {
      tasks = tasks.where((t) => t.priority == _priorityFilter).toList();
    }
    if (_statusFilter != null) {
      tasks = switch (_statusFilter) {
        'done' => tasks.where((t) => t.status == 'done').toList(),
        'overdue' => tasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                t.dueDate!.isBefore(today))
            .toList(),
        _ => tasks.where((t) => t.status != 'done').toList(),
      };
    }
    return tasks;
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TaskFilterSheet(
        priorityFilter: _priorityFilter,
        statusFilter: _statusFilter,
        onChanged: (priority, status) {
          setState(() {
            _priorityFilter = priority;
            _statusFilter = status;
          });
        },
      ),
    );
  }

  List<ActiveFilterChip> _buildChips() {
    final chips = <ActiveFilterChip>[];
    if (_priorityFilter != null) {
      chips.add(ActiveFilterChip(
        label: 'Priorität: ${_priorityLabel(_priorityFilter!)}',
        onRemove: () => setState(() => _priorityFilter = null),
      ));
    }
    if (_statusFilter != null) {
      final label = switch (_statusFilter) {
        'done' => 'Erledigt',
        'overdue' => 'Überfällig',
        _ => 'Offen',
      };
      chips.add(ActiveFilterChip(
        label: label,
        onRemove: () => setState(() => _statusFilter = null),
      ));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);

    final searchBar = SearchAndFilterBar(
      query: _query,
      controller: _searchCtrl,
      onQueryChanged: (v) => setState(() => _query = v),
      hintText: 'Aufgaben suchen…',
      hasActiveFilters: _hasFilters,
      activeFilterChips: _buildChips(),
      onFilterTap: () => _showFilterSheet(context),
    );

    final body = tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (allTasks) {
        final tasks = _applyFilters(allTasks);

        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.task_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(allTasks.isEmpty ? 'Keine Aufgaben' : 'Keine Treffer'),
                if (allTasks.isEmpty) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showAddDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Aufgabe anlegen'),
                  ),
                ],
              ],
            ),
          );
        }

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final overdue = tasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                t.dueDate!.isBefore(today))
            .toList();
        final todayTasks = tasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                _isToday(t.dueDate!))
            .toList();
        final thisWeek = tasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                !_isToday(t.dueDate!) &&
                _isThisWeek(t.dueDate!))
            .toList();
        final later = tasks
            .where((t) =>
                t.status != 'done' &&
                t.dueDate != null &&
                !_isThisWeek(t.dueDate!) &&
                !_isToday(t.dueDate!) &&
                !t.dueDate!.isBefore(today))
            .toList();
        final noDate =
            tasks.where((t) => t.status != 'done' && t.dueDate == null).toList();
        final done = tasks.where((t) => t.status == 'done').toList();

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

    if (widget.embedded) {
      return Column(
        children: [
          searchBar,
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgaben'),
        actions: shellMenuActions(context),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
              _hasFilters || _query.isNotEmpty ? 92 : 60),
          child: searchBar,
        ),
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context) =>
      showAddTaskSheet(context);
}

// ── Task filter sheet ─────────────────────────────────────────────────────────

class _TaskFilterSheet extends StatefulWidget {
  final String? priorityFilter;
  final String? statusFilter;
  final void Function(String? priority, String? status) onChanged;

  const _TaskFilterSheet({
    required this.priorityFilter,
    required this.statusFilter,
    required this.onChanged,
  });

  @override
  State<_TaskFilterSheet> createState() => _TaskFilterSheetState();
}

class _TaskFilterSheetState extends State<_TaskFilterSheet> {
  late String? _priority;
  late String? _status;

  @override
  void initState() {
    super.initState();
    _priority = widget.priorityFilter;
    _status = widget.statusFilter;
  }

  void _apply() {
    widget.onChanged(_priority, _status);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAny = _priority != null || _status != null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text('Filter', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (hasAny)
                  TextButton(
                    onPressed: () {
                      setState(() { _priority = null; _status = null; });
                    },
                    child: const Text('Zurücksetzen'),
                  ),
                FilledButton(
                  onPressed: _apply,
                  child: const Text('Anwenden'),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _FSection('Priorität'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final p in ['low', 'medium', 'high'])
                      FilterChip(
                        label: Text(_priorityLabel(p)),
                        selected: _priority == p,
                        onSelected: (_) =>
                            setState(() => _priority = _priority == p ? null : p),
                        visualDensity: VisualDensity.compact,
                        selectedColor: cs.primaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _FSection('Status'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in [
                      ('open', 'Offen'),
                      ('done', 'Erledigt'),
                      ('overdue', 'Überfällig'),
                    ])
                      FilterChip(
                        label: Text(entry.$2),
                        selected: _status == entry.$1,
                        onSelected: (_) =>
                            setState(() => _status = _status == entry.$1 ? null : entry.$1),
                        visualDensity: VisualDensity.compact,
                        selectedColor: cs.primaryContainer,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FSection extends StatelessWidget {
  final String title;
  const _FSection(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      );
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
                    onTap: hasSubtasks
                        ? () => setState(() => _expanded = !_expanded)
                        : null,
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
                        // Expand indicator — tap on the full tile handles expand
                        if (hasSubtasks)
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.expand_more,
                                size: 18, color: cs.outline),
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

    final desc = task.description;

    if (chips.isEmpty && desc == null) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty) Wrap(spacing: 4, runSpacing: 2, children: chips),
        if (desc != null)
          Text(
            desc,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  void _showDialog(BuildContext context, {String? parentId}) {
    showAddTaskSheet(
      context,
      task: parentId == null ? widget.task : null,
      parentId: parentId,
    ).then((_) {
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
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            label,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
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

            if (widget.task != null) ...[
              const Divider(height: 24),
              EntityPhotoSection(
                  entityId: widget.task!.id, entityType: 'task'),
              const SizedBox(height: 8),
            ],

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
