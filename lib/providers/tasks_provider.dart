import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final tasksProvider = StreamProvider<List<Task>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchTasks();
});

final tasksNotifierProvider =
    AsyncNotifierProvider<TasksNotifier, void>(TasksNotifier.new);

class TasksNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> create({
    required String title,
    String? description,
    DateTime? dueDate,
    bool recurring = false,
    String? recurrenceType,
    String? notes,
  }) async {
    await _db.insertTask(TasksCompanion.insert(
      id: _uuid.v4(),
      title: title,
      description: Value(description),
      dueDate: Value(dueDate),
      recurring: Value(recurring),
      recurrenceType: Value(recurrenceType),
      notes: Value(notes),
    ));
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
      notes: Value(task.notes),
      completedAt: Value(task.completedAt),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> toggleDone(Task task) {
    final isDone = task.status == 'done';
    return save(task.copyWith(
      status: isDone ? 'pending' : 'done',
      completedAt: Value(isDone ? null : DateTime.now()),
    ));
  }

  Future<void> delete(String id) => _db.deleteTask(id);
}
