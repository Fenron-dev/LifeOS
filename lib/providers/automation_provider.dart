import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final automationRulesProvider =
    StreamProvider<List<AutomationRule>>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchAutomationRules();
});

final automationNotifierProvider =
    AsyncNotifierProvider<AutomationNotifier, void>(AutomationNotifier.new);

class AutomationNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<void> create({
    required String name,
    required String triggerType,
    Map<String, dynamic> triggerConfig = const {},
    List<Map<String, dynamic>> conditions = const [],
    List<Map<String, dynamic>> actions = const [],
    bool enabled = true,
  }) async {
    await _db.insertAutomationRule(AutomationRulesCompanion.insert(
      id: _uuid.v4(),
      name: name,
      triggerType: triggerType,
      triggerConfig: Value(jsonEncode(triggerConfig)),
      conditions: Value(jsonEncode(conditions)),
      actions: Value(jsonEncode(actions)),
      enabled: Value(enabled),
    ));
  }

  Future<void> save(AutomationRule rule) async {
    await _db.updateAutomationRule(AutomationRulesCompanion(
      id: Value(rule.id),
      name: Value(rule.name),
      enabled: Value(rule.enabled),
      triggerType: Value(rule.triggerType),
      triggerConfig: Value(rule.triggerConfig),
      conditions: Value(rule.conditions),
      actions: Value(rule.actions),
    ));
  }

  Future<void> toggleEnabled(AutomationRule rule) =>
      save(rule.copyWith(enabled: !rule.enabled));

  Future<void> delete(String id) => _db.deleteAutomationRule(id);

  /// Runs a rule's actions manually. Returns list of result messages.
  Future<List<String>> runNow(AutomationRule rule) async {
    final actions = List<Map<String, dynamic>>.from(
        jsonDecode(rule.actions) as List);
    final results = <String>[];
    for (final action in actions) {
      final msg = await _executeAction(action);
      if (msg != null) results.add(msg);
    }
    await _db.updateAutomationRule(AutomationRulesCompanion(
      id: Value(rule.id),
      lastTriggeredAt: Value(DateTime.now()),
    ));
    return results;
  }

  Future<String?> _executeAction(Map<String, dynamic> action) async {
    final type = action['type'] as String? ?? '';
    switch (type) {
      case 'create_task':
        final title = action['title'] as String? ?? 'Automatische Aufgabe';
        final priority = action['priority'] as String? ?? 'medium';
        final daysOffset = action['daysOffset'] as int? ?? 0;
        final dueDate = daysOffset > 0
            ? DateTime.now().add(Duration(days: daysOffset))
            : null;
        await _db.insertTask(TasksCompanion.insert(
          id: const Uuid().v4(),
          title: title,
          priority: Value(priority),
          dueDate: Value(dueDate),
        ));
        return 'Aufgabe erstellt: $title';

      case 'notify':
        final message = action['message'] as String? ?? '';
        return 'Benachrichtigung: $message';

      default:
        return null;
    }
  }
}
