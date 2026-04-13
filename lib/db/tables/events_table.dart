import 'package:drift/drift.dart';
import 'items_table.dart';

/// Immutable event log — all inventory changes are stored here (append-only).
/// Current state is derived from events + materialized in ItemStates.
class ItemEvents extends Table {
  TextColumn get id => text()();

  // Event types: 'purchase' | 'consumption' | 'stocktake' | 'relocation' |
  //              'state_change' | 'opened' | 'transfer_to_container' | 'expiry_update'
  TextColumn get type => text()();

  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get inventoryEntryId => text()
      .nullable()
      .references(InventoryEntries, #id, onDelete: KeyAction.setNull)();

  RealColumn get quantity => real().nullable()();
  TextColumn get unit => text().nullable()();

  // For purchases
  RealColumn get price => real().nullable()();
  TextColumn get store => text().nullable()();

  // For relocations
  TextColumn get fromLocationId => text().nullable()();
  TextColumn get toLocationId => text().nullable()();

  // For state changes
  TextColumn get fromState => text().nullable()();
  TextColumn get toState => text().nullable()();

  // For container linking
  TextColumn get containerId => text().nullable()(); // FK → Items

  // Sync metadata
  TextColumn get deviceId => text()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))(); // pending | synced | conflict
  DateTimeColumn get syncedAt => dateTime().nullable()();

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Materialized projection of item events — recomputable, used for fast reads.
/// Updated whenever a relevant event is inserted.
class ItemStates extends Table {
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get inventoryEntryId =>
      text().references(InventoryEntries, #id, onDelete: KeyAction.cascade)();
  RealColumn get currentQuantity => real()();
  TextColumn get unit => text()();
  TextColumn get locationId => text().nullable()();
  TextColumn get state => text()(); // fresh | frozen | thawed
  DateTimeColumn get expiryDate => dateTime().nullable()();
  DateTimeColumn get lastEventAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {inventoryEntryId};
}
