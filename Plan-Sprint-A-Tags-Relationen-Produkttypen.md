# Plan: Tags, Item-Relationen, Custom Properties, Produkttypen + kleine Fixes

## Context

Der bisherige Navigationsumbau ist abgeschlossen. Jetzt kommen inhaltliche Verbesserungen:
- **Kleine Fixes**: Haltbarkeiten-Navigation + Scan-FAB-Duplikat entfernen
- **Produkttypen**: 4 neue Typen (Gerät, Werkzeug, Verbrauchsmaterial, Allgemein) + user-manageable Liste
- **Tags**: Schema existiert bereits — Provider + UI nachrüsten
- **Item-Relationen**: Obsidian-style Verlinkungen (bidirektional, freie Notiz)
- **Custom Properties**: Kategorie-Felder als Template + freie Freifelder pro Artikel

Implementierung in zwei Sprints:
- **Sprint A** (dieser Plan, Schema v27): Fixes + Produkttypen + Tags + Relationen
- **Sprint B** (Folgeplan, Schema v28): Custom Properties (Templates, Feldtypen inkl. Tags/Liste/Link) + Produkttypen-Verwaltung in Einstellungen

---

## Teil 0: Kleine Fixes (keine Schema-Änderung)

### Fix 1: ShelfLifeScreen → Tap navigiert zu Artikel-Detail

**Datei:** `lib/screens/inventory/shelf_life_screen.dart`

In `_ShelfLifeTile.build()` dem `ListTile` ein `onTap` hinzufügen:
```dart
onTap: () => context.push('/haushalt/item/${item.id}'),
```
Route `/haushalt/item/:id` existiert bereits im Router.

### Fix 2: InventoryScreen — Scan-FAB entfernen

**Datei:** `lib/screens/inventory/inventory_screen.dart`

Die bisherige FAB-Logik zeigt einen Scan-FAB wenn `scanBarcode` nicht in Quick Actions.
Da das Scan-Icon jetzt permanent in der SearchBar sitzt, ist der Scan-FAB redundant.

Neue vereinfachte FAB-Logik:
```dart
floatingActionButton: hasAddAction ? null : FloatingActionButton(
  heroTag: 'add',
  onPressed: () => context.push('/haushalt/item/new'),
  tooltip: 'Artikel hinzufügen',
  child: const Icon(Icons.add),
),
```
`hasScanAction`-Variable und der gesamte Scan-FAB-Branch werden entfernt.

---

## Teil 1: Produkttypen erweitern

### 1a — Neue Typen als Konstanten

**Datei:** `lib/core/product_types.dart` (neu)

Neue Klasse `ProductType` (analog zu `ItemCategory`):

```dart
class ProductType {
  static const readyToEat         = 'readyToEat';   // Fertiggericht (bestehend)
  static const needsCooking       = 'needsCooking';  // Muss gekocht werden (bestehend)
  static const ingredient         = 'ingredient';    // Zutat (bestehend)
  static const device             = 'device';        // Gerät / Ausstattung (NEU)
  static const tool               = 'tool';          // Werkzeug / Zubehör (NEU)
  static const consumableNonFood  = 'consumable';    // Verbrauchsmaterial (NEU)
  static const general            = 'general';       // Allgemein / Sonstiges (NEU)

  static String labelDe(String id) => switch(id) {
    readyToEat        => 'Fertiggericht',
    needsCooking      => 'Muss gekocht werden',
    ingredient        => 'Zutat',
    device            => 'Gerät / Ausstattung',
    tool              => 'Werkzeug / Zubehör',
    consumableNonFood => 'Verbrauchsmaterial',
    general           => 'Allgemein / Sonstiges',
    _                 => id,
  };

  static IconData iconFor(String id) => switch(id) { ... };
  
  static const all = [readyToEat, needsCooking, ingredient, device, tool, consumableNonFood, general];
}
```

**Anpassungen** (überall wo productType-String geprüft wird):
- `lib/screens/inventory/inventory_screen.dart` — `_ProductTypeIcon`
- `lib/screens/items/item_form_screen.dart` — productType-Dropdown
- `lib/screens/items/item_detail_screen.dart` — Anzeige Produkttyp

### 1b — Schema: ProductTypeDefinitions-Tabelle (v28, Sprint B)

*Für Sprint B geplant:* Neue Tabelle `ProductTypeDefinitions` für user-verwaltete Typen + Settings-Screen. In Sprint A nur die hardcodierten Konstanten.

---

## Teil 2: Tags — Provider + UI (Schema existiert bereits, kein v27 nötig)

### 2a — Datenbank-Methoden

**Datei:** `lib/db/database.dart` — Analoge Methoden wie die bestehenden Recipe-Tag-Methoden:

```dart
// Tags für ein Item lesen (Stream)
Stream<List<TagDefinition>> watchTagsForItem(String itemId)

// Alle Tag-Definitionen für eine Kategorie
Stream<List<TagDefinition>> watchTagDefinitions(String categoryId)

// Tags für ein Item atomar setzen (analog setTagsForRecipe)
Future<void> setTagsForItem(String itemId, String categoryId, List<String> tagNames)

// Tag-Definition finden oder erstellen
Future<String> _ensureItemTag(String name, String categoryId)
```

### 2b — Provider

**Neue Datei:** `lib/providers/tags_provider.dart`

```dart
// Tags für ein Item (StreamProvider.family)
final tagsForItemProvider = StreamProvider.family<List<TagDefinition>, String>(...);

// Alle Tag-Definitionen für eine Kategorie
final tagDefinitionsProvider = StreamProvider.family<List<TagDefinition>, String>(...);

// CRUD-Notifier
final tagsNotifierProvider = AsyncNotifierProvider<TagsNotifier, void>(...);
// Methoden: setTagsForItem, deleteTagDefinition, updateTagColor
```

### 2c — Tag-UI im Artikel-Detail

**Datei:** `lib/screens/items/item_detail_screen.dart`

Neue Section `_TagsSection` (ConsumerWidget):
- Zeigt Tag-Chips (Material 3 `InputChip` mit Farbe + Icon wenn vorhanden)
- Tap auf Chip → Tag entfernen (mit Bestätigung)
- „+ Tag hinzufügen" Button → öffnet `_TagPickerSheet`

```
┌─ Tags ────────────────────────────────────┐
│ [🟢 Bio] [🔵 Kühlschrank] [+ hinzufügen] │
└───────────────────────────────────────────┘
```

**`_TagPickerSheet`** (ModalBottomSheet):
- Suche nach bestehenden Tags der Kategorie
- Autocomplete + „Neu erstellen: X" wenn kein Match
- Multi-Select möglich

### 2d — Tag-Feld im Artikel-Formular

**Datei:** `lib/screens/items/item_form_screen.dart`

Nach den bestehenden Feldern einen neuen Abschnitt „Tags":
- Aktuelle Tags als abwählbare InputChips
- `+` Button öffnet Tag-Picker analog zu 2c

### 2e — Tag-Filter im Inventar

**Datei:** `lib/screens/inventory/inventory_screen.dart`

`_CategoryFilterRow` erweitern:
- Nach Kategorie-Chips eine zweite Zeile für Tag-Chips
- `itemTagFilterProvider` (StateProvider<String?>) — ausgewählter Tag
- `filteredItemsProvider` berücksichtigt beide Filter (Kategorie AND Tag)

---

## Teil 3: Item-Relationen (Schema v27)

### 3a — Neue Tabelle

**Neue Datei:** `lib/db/tables/relations_table.dart`

```dart
class ItemRelations extends Table {
  TextColumn get id => text()();
  TextColumn get fromItemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get toItemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get notes => text().nullable()();   // freie Notiz (Obsidian-style)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
```

**Migration v27 in `database.dart`:**
```dart
if (from < 27) {
  await m.createTable(itemRelations);
}
```
`schemaVersion` → 27. Smoke-Test anpassen.

### 3b — Datenbank-Methoden

In `database.dart`:
```dart
// Alle Relationen eines Items (in beide Richtungen)
Future<List<ItemRelationWithItem>> relationsForItem(String itemId)
  // = alle Rows wo fromItemId == itemId OR toItemId == itemId
  // Mit JOIN auf Items, um den Gegenpart-Item-Namen zu liefern

Future<void> addItemRelation(String fromId, String toId, {String? notes})
Future<void> deleteItemRelation(String relationId)
Future<void> updateItemRelationNotes(String id, String? notes)
```

### 3c — Provider

**Neue Datei:** `lib/providers/relations_provider.dart`

```dart
final relationsForItemProvider =
    FutureProvider.family<List<ItemRelationWithItem>, String>(...);

final relationsNotifierProvider =
    AsyncNotifierProvider<RelationsNotifier, void>(...);
```

### 3d — UI im Artikel-Detail

**Datei:** `lib/screens/items/item_detail_screen.dart`

Neue Section `_RelationsSection`:

```
┌─ Verwandte Artikel ────────────────────────────────────┐
│ [→ Nespresso Maschine]  Kapseln dafür       [✎] [✕]  │
│ [→ HDMI Kabel 2m]       Kompatibel           [✎] [✕]  │
│ [+ Artikel verlinken]                                   │
└────────────────────────────────────────────────────────┘
```

Jeder Eintrag:
- Tap → navigiert zum verknüpften Artikel
- `[✎]` → Notiz bearbeiten
- `[✕]` → Relation löschen

„+ Artikel verlinken" öffnet `_RelationPickerSheet`:
- Suche nach Artikel-Namen
- Optionales Notiz-Feld
- Speichern

---

## Teil 4: Custom Properties + Templates — Sprint B

*Wird im Folgesprint geplant und umgesetzt.*

### Konzept: Templates ≠ Kategorien

| | Kategorie | Template |
|---|---|---|
| Zweck | Klassifizierung / Filter | Vordefinierte Felder-Vorlage |
| Beispiele | Lebensmittel, Elektronik, Haushalt | Laptop, Netzteil, Verbrauchsmaterial |
| Pflicht? | Ja (1 pro Artikel) | Optional (0–1 pro Artikel) |
| Felder definiert? | Nein | Ja (mit Typ + Pflichtfeld-Flag) |
| Anwendung | Inventar-Filter, Tag-Scoping | Properties im Artikel vorbefüllen |

Ein Template legt fest *welche Felder* ein Artikel hat. Kategorien legen fest *wie er gruppiert/gefiltert* wird. Beide können unabhängig voneinander gesetzt werden.

### 4a — Feldtypen

```
text        — einzeiliger Freitext (z.B. Seriennummer)
number      — Zahl mit optionaler Einheit (z.B. "16 GB RAM")
date        — Datum (z.B. Kaufdatum, Garantieende)
boolean     — Ja/Nein-Schalter (z.B. "Hat Netzteil?")
tags        — eigenständiges Multi-Tag-Feld (separat von normalen item_tags)
liste       — geordnete Liste von Texteinträgen (z.B. Kompatible Modelle)
link        — entweder interner Artikel-Link (itemId) ODER externe URL (String)
              → gespeichert als JSON: {"type":"item","id":"..."} oder {"type":"url","href":"..."}
```

### 4b — Schema (v28, Sprint B)

**Neue Tabellen:**

```dart
// item_templates — Template-Definitionen (user-verwaltbar)
class ItemTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();           // z.B. "Laptop", "Netzteil"
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable()(); // optionale Kategorie-Vorbelegung
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}

// template_fields — Felder pro Template
class TemplateFields extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().references(ItemTemplates, #id, onDelete: KeyAction.cascade)();
  TextColumn get fieldName => text()();      // z.B. "Seriennummer", "RAM"
  TextColumn get fieldType => text()();      // text|number|date|boolean|tags|liste|link
  TextColumn get defaultValue => text().nullable()();
  BoolColumn get required => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  @override Set<Column> get primaryKey => {id};
}

// item_property_values — Werte pro Artikel (Template-Felder + freie Felder)
class ItemPropertyValues extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get fieldKey => text()();       // fieldName aus Template oder freier Schlüssel
  TextColumn get fieldType => text()();      // redundant aber nötig für freie Felder
  TextColumn get value => text()();          // JSON-encoded für tags/liste/link, plain für rest
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

**Items-Tabelle (v28):**
- Neue Spalte `templateId TEXT NULLABLE REFERENCES item_templates(id) ON DELETE SET NULL`

### 4c — UI

**Einstellungen → Templates:**
- Liste aller Templates (built-in + user-erstellt)
- Template anlegen/bearbeiten: Name, Felder mit Typ + Pflichtfeld-Flag + Reihenfolge
- Built-in Templates (nicht löschbar): Laptop, Smartphone, Haushaltsgerät, Werkzeug, ...

**Artikel-Formular (item_form_screen.dart):**
- Neues Feld „Template" (Dropdown) — wählt Template aus, befüllt Properties-Abschnitt
- Properties-Abschnitt zeigt Template-Felder + Freifeld-Button „+ eigenes Feld"

**Artikel-Detail (item_detail_screen.dart):**
- `_PropertiesSection`: Template-Felder + freie Felder, gruppiert
- Link-Felder: interner Link → NavigationChip (Tap öffnet Artikel-Detail); externer Link → `url_launcher`-Link mit Hersteller-Icon
- Tags-Felder: eigene Tag-Chips (nicht vermischt mit item_tags)
- Liste-Felder: geordnete Bullet-List mit Add/Remove/Reorder

**Filter (Inventar):**
- Property-Filter: Wert eines Felds einschränken (z.B. `RAM = "16 GB"`)
- Template-Filter: nur Artikel eines bestimmten Templates anzeigen

### 4d — Produkttypen user-verwaltbar (Sprint B, Settings)

**Neue Tabelle `product_type_definitions`** (v28):
```dart
class ProductTypeDefinitions extends Table {
  TextColumn get id => text()();             // z.B. "device", "laptop_custom"
  TextColumn get nameDe => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get iconName => text().nullable()(); // Material icon name
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  @override Set<Column> get primaryKey => {id};
}
```
- `onCreate` seed: alle 7 bestehenden Typen mit `isBuiltIn = true`
- Einstellungen → Produkttypen: Liste + Add/Edit (nur user-defined) + Delete

---

## Betroffene Dateien (Sprint A)

| Datei | Änderung |
|---|---|
| `lib/screens/inventory/shelf_life_screen.dart` | `onTap` Navigation hinzufügen |
| `lib/screens/inventory/inventory_screen.dart` | Scan-FAB entfernen, Tag-Filter ergänzen |
| `lib/core/product_types.dart` | NEU — 7 Produkttypen als Konstanten |
| `lib/screens/items/item_detail_screen.dart` | Tag-Section + Relations-Section |
| `lib/screens/items/item_form_screen.dart` | Tag-Feld |
| `lib/db/database.dart` | Tag-DAOs + Relations-DAOs, schemaVersion → 27 |
| `lib/db/tables/relations_table.dart` | NEU |
| `lib/providers/tags_provider.dart` | NEU |
| `lib/providers/relations_provider.dart` | NEU |
| `test/db/database_smoke_test.dart` | Version 27 |

---

## Reihenfolge der Umsetzung

1. **Fix 1+2**: ShelfLife-Navigation + FAB-Bereinigung
2. **Produkttypen**: Neue Konstanten + alle Verwendungsstellen aktualisieren
3. **Tags**: DB-Methoden → Provider → Detail-UI → Form-UI → Inventar-Filter
4. **Relationen**: Schema v27 → build_runner → DB-Methoden → Provider → Detail-UI
5. `flutter analyze` + `flutter test` + commit + push

---

## Verifikation

```bash
# Schema + Tests
flutter test test/db/database_smoke_test.dart

# Statische Analyse
flutter analyze lib/

# Manuelle Checks:
# - Haltbarkeiten: Artikel antippen → öffnet Artikel-Detail
# - Inventar: kein Scan-FAB mehr sichtbar
# - Artikel anlegen: alle 7 Produkttypen in der Auswahl
# - Artikel-Detail: Tags anzeigen, hinzufügen, entfernen
# - Artikel-Formular: Tags bearbeiten
# - Inventar: Tag-Filter einschränkt Liste korrekt
# - Artikel-Detail: Relation hinzufügen, Tap navigiert zu verlinktem Artikel
# - Relation löschen → beide Seiten verschwinden
```
