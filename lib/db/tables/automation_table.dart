import 'package:drift/drift.dart';

/// If→Then automation rules
class AutomationRules extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  // Trigger type: 'manual' | 'scheduled' | 'event' | 'threshold'
  TextColumn get triggerType => text()();
  // Trigger config: JSON (cron expression, event type, threshold condition)
  TextColumn get triggerConfig => text().withDefault(const Constant('{}'))();
  // Conditions: JSON array of filter objects [{field, operator, value}]
  TextColumn get conditions => text().withDefault(const Constant('[]'))();
  // Actions: JSON array of action objects [{type, params}]
  TextColumn get actions => text().withDefault(const Constant('[]'))();
  DateTimeColumn get lastTriggeredAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// App settings (key-value store)
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
