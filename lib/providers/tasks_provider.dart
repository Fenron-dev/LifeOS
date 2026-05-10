import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

int _priorityRank(String p) => switch (p) {
      'high' => 0,
      'medium' => 1,
      _ => 2,
    };

List<Task> _sortTasks(List<Task> list) {
  list.sort((a, b) {
    final sa = a.status == 'done' ? 1 : 0;
    final sb = b.status == 'done' ? 1 : 0;
    if (sa != sb) return sa.compareTo(sb);
    final pa = _priorityRank(a.priority);
    final pb = _priorityRank(b.priority);
    if (pa != pb) return pa.compareTo(pb);
    if (a.dueDate == null && b.dueDate == null) return 0;
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  });
  return list;
}

/// Root-level tasks only (no subtasks).
final tasksProvider = StreamProvider<List<Task>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchRootTasks().map(_sortTasks);
});

/// Subtasks for a given parent task id.
final subtasksProvider =
    StreamProvider.family<List<Task>, String>((ref, parentId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchSubtasks(parentId).map(_sortTasks);
});

final tasksNotifierProvider =
    AsyncNotifierProvider<TasksNotifier, void>(TasksNotifier.new);

class TasksNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<String> create({
    required String title,
    String? description,
    DateTime? dueDate,
    bool recurring = false,
    String? recurrenceType,
    int? recurrenceInterval,
    String priority = 'medium',
    String? notes,
    String? parentId,
    String? linkedItemId,
  }) async {
    final id = _uuid.v4();
    await _db.insertTask(TasksCompanion.insert(
      id: id,
      title: title,
      description: Value(description),
      dueDate: Value(dueDate),
      recurring: Value(recurring),
      recurrenceType: Value(recurrenceType),
      recurrenceInterval: Value(recurrenceInterval),
      priority: Value(priority),
      notes: Value(notes),
      parentId: Value(parentId),
      linkedItemId: Value(linkedItemId),
    ));
    return id;
  }

  Future<void> save(Task task) async {
    await _db.updateTask(TasksCompanion(
      id: Value(task.id),
      title: Value(task.title),
      description: Value(task.description),
      status: Value(task.status),
      dueDate: Value(task.dueDate),
      recurring: Value(task.recurring),
      recurrenceType: Value(task.recurrenceType),
      recurrenceInterval: Value(task.recurrenceInterval),
      priority: Value(task.priority),
      notes: Value(task.notes),
      completedAt: Value(task.completedAt),
      updatedAt: Value(DateTime.now()),
      parentId: Value(task.parentId),
      linkedItemId: Value(task.linkedItemId),
    ));
  }

  Future<void> toggleDone(Task task) async {
    final isDone = task.status == 'done';
    await save(task.copyWith(
      status: isDone ? 'pending' : 'done',
      completedAt: Value(isDone ? null : DateTime.now()),
    ));
    // Auto-create next occurrence when marking a recurring task done
    if (!isDone && task.recurring && task.recurrenceType != null) {
      final next = _nextDueDate(task);
      if (next != null) {
        await create(
          title: task.title,
          description: task.description,
          dueDate: next,
          recurring: true,
          recurrenceType: task.recurrenceType,
          recurrenceInterval: task.recurrenceInterval,
          priority: task.priority,
          notes: task.notes,
          linkedItemId: task.linkedItemId,
        );
      }
    }
  }

  Future<void> delete(String id) => _db.deleteTask(id);

  static DateTime? _nextDueDate(Task task) {
    final base = task.dueDate ?? DateTime.now();
    final n = task.recurrenceInterval ?? 1;
    return switch (task.recurrenceType) {
      'daily' => base.add(Duration(days: n)),
      'weekly' => base.add(Duration(days: 7 * n)),
      'monthly' => DateTime(base.year, base.month + n, base.day),
      'yearly' => DateTime(base.year + n, base.month, base.day),
      _ => null,
    };
  }
}
