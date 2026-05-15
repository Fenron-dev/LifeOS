# Sprint E — Einkaufsliste-Scan, Workout-Timer, Pläne, Bewertungen, Dashboard, Grundnahrungsmittel

## Status

| Teil | Feature | Status |
|------|---------|--------|
| 1 | Schema v37 (Items: isStaple, purchaseUnit, purchaseQty) | ✅ Fertig |
| 2 | Workout-Timer manuell starten | Ausstehend |
| 3a | Plan-Übungen automatisch laden beim Start | Ausstehend |
| 3b | Template-Pläne ohne Wochentag (dayOfWeek nullable) | Ausstehend |
| 4a | Übungen: isFavorite / starRating / thumbRating | Ausstehend |
| 4b | Übungsbibliothek Filter (Favoriten, Sterne, Daumen) | Ausstehend |
| 4c | Trainingspläne: isFavorite / starRating / thumbRating | Ausstehend |
| 5 | Übungsdetail-Wiki (shortDescription + verbesserte Ansicht) | Ausstehend |
| 6a | Einkaufsliste: Scan zum Hinzufügen | ✅ Fertig |
| 6b | Einkaufsliste: LinkedItemCard auto-entfernen nach Einbuchen | ✅ Fertig |
| 6b² | Einkaufsliste: NeedCard Packungsanzahl (purchaseUnit/purchaseQty) | ✅ Fertig |
| 6c | Einkaufsliste: CustomItemTile "Mit Artikel verknüpfen" | ✅ Fertig |
| 7 | Dashboard: _TodayHealthCard (kcal heute + Workouts) | Ausstehend |
| 8a | Artikelformular: isStaple Toggle + purchaseUnit + purchaseQty | ✅ Fertig |
| 8b | Dashboard: _StapleWarningCard (missingStaplesProvider) | Ausstehend |

---

## Teil 1 — Schema v37 (Items only, Sprint E Phase 1)

### `lib/db/tables/items_table.dart`

Neue Felder:
```dart
BoolColumn get isStaple => boolean().withDefault(const Constant(false))();
TextColumn get purchaseUnit => text().nullable()();
RealColumn get purchaseQty => real().nullable()();
```

### `lib/db/database.dart`

- `schemaVersion` → 37
- Migration:
```dart
if (from < 37) {
  await m.addColumn(items, items.isStaple);
  await m.addColumn(items, items.purchaseUnit);
  await m.addColumn(items, items.purchaseQty);
}
```

---

## Teil 2 — Workout-Timer manuell starten

**Schema-Erweiterung** (`fitness_table.dart`):
```dart
// Null = Timer noch nicht gestartet
DateTimeColumn get timerStartedAt => dateTime().nullable()();
```

**`lib/health/screens/workouts_tab.dart`** — `_ActiveWorkoutScreenState`:
- Stopwatch nicht auto-starten
- `_timerRunning = false` State
- `initState`: wenn `workout.timerStartedAt != null`, Timer-State wiederherstellen
- „Training starten" Button (wenn `!_timerRunning`)
- `_WorkoutTimer` zeigt `DateTime.now().difference(_timerStartedAt!)` statt `stopwatch.elapsed`

**`WorkoutOpsNotifier.finishWorkout()`:** Duration aus `timerStartedAt` berechnen.

---

## Teil 3 — Trainingspläne: Auto-Load + Template-Pläne

### 3a — Auto-Load Plan-Übungen

**`fitness_table.dart`** — `WorkoutPlanExercises`:
```dart
// Null = kein bestimmter Tag (Template-Übung)
IntColumn get dayOfWeek => integer().nullable()();
```
→ `alterTable` Migration erforderlich

**`lib/db/database.dart`**:
```dart
Future<List<WorkoutPlanExercise>> planExercisesForDay(String planId, int dayOfWeek);
```

**`ActiveWorkoutScreen`**: Sektion „Heutige Übungen" wenn `workout.planId != null`.

### 3b — Template-Pläne

- Wochentag-Picker: extra Option „– Kein Tag –" (sendet `null`)
- Sektion „Immer / Template" für Übungen mit `dayOfWeek == null`
- `WorkoutOpsNotifier.addPlanExercise()`: `int? dayOfWeek`

---

## Teil 4 — Bewertungen: Exercises + Plans

### `fitness_table.dart` — Exercises neue Felder:
```dart
TextColumn get shortDescription => text().nullable()();
BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
IntColumn get starRating => integer().nullable()();  // 1–5
IntColumn get thumbRating => integer().nullable()();  // -1 | 0 | 1
```

### `fitness_table.dart` — WorkoutPlans neue Felder:
```dart
BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
IntColumn get starRating => integer().nullable()();
IntColumn get thumbRating => integer().nullable()();
```

### UI (workouts_tab.dart):
- `ExerciseDetailScreen`: Herz-Icon, `_ThumbRow`, `_StarRow`
- `ExerciseLibraryScreen`: Filter-Chips (❤️ Favoriten, ★ 4+, 👍 Empfohlen)
- `WorkoutPlanDetailScreen`: Favorit-Icon, `_StarRow`, `_ThumbRow`

---

## Teil 5 — Übungsdetail-Wiki

**`ExerciseDetailScreen`**:
- Kursivierter 1-Zeiler `exercise.shortDescription` unter Titel
- Bearbeiten-Dialog: neues `shortDescription`-Textfeld
- `instructions` → „Ausführung", `tips` → „Tipps & Hinweise"
- `videoUrl`: `ListTile` mit `Icons.play_circle_outline` → `launchUrl()`

---

## Teil 6 — Einkaufsliste (Sprint E Phase 1, bereits fertig)

### 6a — Scan zum Hinzufügen

**`ShoppingListScreen`**:
- AppBar: Scan-Icon neben + Button
- Embedded: drittes FAB (scan)
- `_scanToAdd()`: Scan → EAN → Item-Suche → insert oder „Anlegen?" SnackBar

### 6b — LinkedItemCard: Auto-Entfernen

- `AddStockSheet._save()` → `Navigator.pop(context, true)`
- `_LinkedItemCard` Einlagern-Button: awaitet `showModalBottomSheet<bool>` → löscht bei `true`

### 6b² — NeedCard: Packungsanzahl

- Wenn `item.purchaseUnit != null && item.purchaseQty != null`:
  - `ceil(neededQty / purchaseQty)` Packungen
  - Hinweistext: `(= neededQty unit)`

### 6c — CustomItemTile: Artikel verknüpfen

- PopupMenu: „Mit Artikel verknüpfen" → `_ItemSearchSheet` → `updateCustomShoppingItem(itemId: ...)`

---

## Teil 7 — Dashboard: Kalorien + Workouts

**`lib/screens/dashboard/start_screen.dart`** — neue Karte `_TodayHealthCard`:
```dart
Row(children: [
  _StatTile(icon: Icons.local_fire_department_outlined, label: 'kcal heute', value: '$consumed kcal'),
  _StatTile(icon: Icons.fitness_center_outlined, label: 'Workouts', value: '$count'),
])
```
- kcal: `nutritionLogsForRangeProvider((today, tomorrow))`
- Workouts: `workoutsProvider` gefiltert auf heute
- Tap → `/ich`

---

## Teil 8 — Grundnahrungsmittel (Sprint E Phase 1, bereits fertig)

### 8a — Artikelformular

Neue Felder (nach Mindestbestand-Sektion):
- `SwitchListTile` „Grundnahrungsmittel" (`isStaple`)
- `TextFormField` „Kaufeinheit" (`purchaseUnit`)
- `TextFormField` numerisch „Stück pro Kaufeinheit" (`purchaseQty`)

### 8b — Dashboard-Warnung

**`lib/db/database.dart`**:
```dart
Stream<List<Item>> watchMissingStapleItems();
// Artikel mit isStaple=true und currentQty=0 (kein Bestand)
```

**`start_screen.dart`**:
- `missingStaplesProvider` → `StreamProvider(db.watchMissingStapleItems())`
- `_StapleWarningCard` ganz oben (vor `_ExpiryCard`)
  - Nur wenn `missingStaples.isNotEmpty`
  - Icon `Icons.warning_amber_rounded`, Farbe `cs.error`
  - Tap → `/haushalt/shopping`

---

## Alle betroffenen Dateien (Gesamtsprint)

| Datei | Änderung |
|-------|---------|
| `lib/db/tables/fitness_table.dart` | +shortDescription/isFavorite/starRating/thumbRating auf Exercises und WorkoutPlans; +timerStartedAt auf Workouts; dayOfWeek nullable auf WorkoutPlanExercises |
| `lib/db/tables/items_table.dart` | +isStaple, +purchaseUnit, +purchaseQty ✅ |
| `lib/db/database.dart` | schemaVersion 37 ✅, Migration ✅, +watchMissingStapleItems, +planExercisesForDay, +setWorkoutTimerStart |
| `lib/health/providers/workouts_provider.dart` | finishWorkout nutzt timerStartedAt; addPlanExercise dayOfWeek → int? |
| `lib/health/screens/workouts_tab.dart` | ActiveWorkoutScreen Timer manuell; Plan-Übungen Sektion; Template-Tag; ExerciseDetail Wiki+Bewertung; PlanDetail Bewertung; Bibliothek Filter |
| `lib/screens/items/item_form_screen.dart` | +isStaple Toggle, +purchaseUnit, +purchaseQty ✅ |
| `lib/providers/items_provider.dart` | createItem/updateItem +isStaple, +purchaseUnit, +purchaseQty ✅ |
| `lib/screens/inventory/shopping_list_screen.dart` | Scan-Add FAB/Button ✅; LinkedItemCard auto-entfernen ✅; NeedCard Packungsanzahl ✅; CustomItem Verknüpfung ✅ |
| `lib/screens/dashboard/start_screen.dart` | +_TodayHealthCard; +_StapleWarningCard; +missingStaplesProvider |
| `test/db/database_smoke_test.dart` | schemaVersion → 37 ✅ |
