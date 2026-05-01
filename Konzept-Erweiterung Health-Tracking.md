---
created-date: 2026-05-01
modified-date: 2026-05-01
status: Freigegeben – Implementierung Phase 6.1 startet
---
# Konzept-Erweiterung: Health-Tracking-Modul

> **Status:** Freigegeben. Diese Datei ergänzt das [Projektkonzept - Local-First Household & Life Management System.md](Projektkonzept%20-%20Local-First%20Household%20%26%20Life%20Management%20System.md) um ein Health-Modul (Phase 6+) und konkretisiert die Sync-Architektur (Phase 5) anhand des Sister-Projekts `pomtechflow_mobile`.

---

# 1. Ziel & Scope

LifeOS wird um einen **persönlichen Gesundheits-Bereich** erweitert (UX-Inspiration: FatSecret). Der Bereich bündelt:

- Gewicht inkl. Körperzusammensetzung (KFA, Muskelmasse, Viszeralfett)
- Manuelle Körpermaße (Brust, Bauch, Oberschenkel, Arm)
- Ernährungstagebuch mit Mahlzeiten-Slots, Makros, Wasser
- OpenFoodFacts-Lebensmittelsuche (zusätzlich zum bestehenden Barcode-Scan)
- Körperfotos (privat, verschlüsselt, lokal)
- Fitness-Tracking (Übungen, Workouts, Sets)
- Diätpläne & Kalorienziele

**Kernprinzip:** alles in einem zentralen Tab "Ich" gebündelt – sensible Daten an einer Stelle, leicht zu sichern, leicht zu schützen.

## 1.1 Modulare Sub-System-Architektur

LifeOS ist von Anfang an als modulares System geplant. Health ist das **erste** zusätzliche Sub-System neben dem Kern (Haushalt/Inventar/Rezepte). Geplant für später: **Bookmarks**, **FAQs/Wissensbasis**, **Haushaltstipps**, ggf. weitere persönliche Domänen.

**Konsequenzen für die Code-Struktur:**

```
lib/
├── core/                    ← Vault, DB-Engine, Auth, gemeinsame Services
├── inventory/               ← Haushalt/Lebensmittel/Inventar (bestehend, ggf. extrahieren)
├── health/                  ← NEU: alles Health-Spezifische gekapselt
│   ├── db/                  ← health-spezifische Drift-Tabellen
│   ├── providers/           ← Riverpod-Provider
│   ├── screens/             ← UI-Screens (Tagebuch, Gewicht, Workouts …)
│   ├── widgets/             ← health-spezifische Widgets
│   └── services/            ← Berechnungen (BMR/TDEE), OFF-Search-Erweiterung
└── widgets/adaptive_shell.dart  ← orchestriert die Sub-System-Tabs
```

**Regeln:**
- Sub-Systeme dürfen **nicht querbeziehen** (kein direkter Import von `inventory/` in `health/` und umgekehrt). Gemeinsame Konzepte (z.B. `Items` mit Nährwerten) leben in `core/`.
- Jedes Sub-System hat **eigene Drift-Tabellen** in eigener Datei unter `lib/<modul>/db/tables/`.
- **Schema-Versionen bleiben global** (eine `schemaVersion` für alle Tabellen, da gemeinsame DB).
- Sub-Systeme müssen **deaktivierbar** bleiben (Vault-Setting `enabledModules: ['inventory', 'health']`) – Tabs verbergen sich, DB-Tabellen bleiben.

Diese Trennung erleichtert spätere Module (Bookmarks etc.) deutlich und verhindert das Diffundieren der Health-Logik in den Haushalts-Code.

---

# 2. Tab-Architektur "Ich"

Der "Ich"-Tab ersetzt das bisherige `stats_screen.dart` und wird zum Hub mit Untertabs (FatSecret-orientiert):

```
[Ich]
├── Tagebuch        ← Tagesansicht: Mahlzeiten, Wasser, Workouts (Default-Screen)
├── Gewicht         ← Chart, Eingabe, Streak
├── Maße            ← Brust/Bauch/OS/Arm + Trend
├── Fotos           ← Privater verschlüsselter Bildbereich (Lock)
├── Workouts        ← Trainings-Sessions, Übungs-Bibliothek
├── Ziele           ← Kalorienziel, Wasserziel, Diätplan, Zielgewicht
└── Profil          ← Größe, Geschlecht, Geburtsdatum, BMR, Aktivitätslevel
```

**Lock-Verhalten:** der gesamte "Ich"-Tab fordert beim ersten Aufruf pro Session Biometrie/PIN (`local_auth`). Andere Tabs bleiben offen. Setting-Schalter "Ich-Tab schützen: an/aus".

---

# 3. Tagebuch-Screen (Hauptansicht)

```
┌─────────────────────────────────────────┐
│ Heute · Mo Di Mi Do Fr Sa So  [✓Streak]│  ← Wochen-Streak-Leiste
├─────────────────────────────────────────┤
│ [Donut: KH 45% Fett 30% Eiweiß 25%]    │
│ Verbleibend: 1245 kcal von 2200        │
├─────────────────────────────────────────┤
│ ☀️  Frühstück            445 kcal  [+] │
│   • Haferflocken 80g  · 304 kcal       │
│   • Banane         · 141 kcal          │
├─────────────────────────────────────────┤
│ 🌞  Mittagessen          —      [+]    │
│ 🌙  Abendessen           —      [+]    │
│ 🍫  Snacks/Sonstiges     —      [+]    │
│ 🍽  Angepasste Mahlzeiten —     [+]    │
├─────────────────────────────────────────┤
│ 💧  Wasser           7/8 Gläser  [+] │
├─────────────────────────────────────────┤
│ 🏋  Training/Schlaf      —      [+]   │
└─────────────────────────────────────────┘
```

**[+]-Button** öffnet die Lebensmittel-Suche (siehe §4).

**Tracking-Anzeige (entschärft, nicht-aufdringlich):**
- Statt FatSecret-Streak ("X Tage am Stück, sonst Reset") nutzen wir eine **monatliche Erfassungsquote**: "18 von 28 Tagen erfasst" + dezenter Smiley/Indikator.
- Optional zusätzlich kurzes **Wochen-Highlight** in der oberen Leiste (Mo–So mit Häkchen je erfasstem Tag), aber **kein "Streak verloren"-Reset und keine Penalty-UX**.
- Ein dezenter motivierender Hinweis ist erlaubt ("3 Tage in Folge erfasst – stark!"), aber **keine roten Warnfarben, kein Schock-Effekt** beim Bruch.
- Setting: "Tracking-Anzeige: an/aus" – wer es ganz weghaben will, kann es deaktivieren.

---

# 4. Lebensmittel-Suche (Add-Sheet)

Bottom-Sheet, das beim "+" auf einer Mahlzeit aufgeht. Tabs:

| Tab | Quelle |
|-----|--------|
| **Lebensmittel** | Lokale `Items` (Inventar + manuell hinzugefügte) + OpenFoodFacts-Online-Suche |
| **Rezepte** | Lokale `Recipes` |
| **Mahlzeiten** | Lokale `StandardMeals` (z.B. "Mein Frühstück") |
| **Kürzlich** | Letzte 30 geloggten Einträge des Users |

**Bottom-Aktionen:** `[📷 Foto-AI]` (später) · `[✨ Quick-Add]` (manuell kcal+Makros) · `[📊 Barcode]`.

**OpenFoodFacts-Suche:** `https://world.openfoodfacts.org/cgi/search.pl?search_terms={q}&json=1&page_size=20`. Treffer können mit einem Tap als neues `Item` ins Inventar aufgenommen werden (auch ohne dass es eingekauft wurde – flag `addedManually=true`, `inStock=false`).

---

# 5. Datenmodell-Erweiterung (Drift)

## 5.1 Bestehende Tabelle erweitern: `BodyWeightLogs`

```dart
// neue optionale Felder ergänzen
RealColumn get bodyFatPct => real().nullable()();      // % Körperfett
RealColumn get muscleMassPct => real().nullable()();   // % Muskelmasse
RealColumn get visceralFat => real().nullable()();     // Viszeralfett-Index (Waagen-typisch 1–30)
RealColumn get waterPct => real().nullable()();        // optional, viele Waagen liefern das
RealColumn get boneMassKg => real().nullable()();      // optional
TextColumn get source => text().withDefault(const Constant('manual'))(); // manual|scale|import
```

## 5.2 Neue Tabelle: `BodyMeasurements`

```dart
class BodyMeasurements extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();
  RealColumn get chestCm => real().nullable()();
  RealColumn get waistCm => real().nullable()();
  RealColumn get hipCm => real().nullable()();
  RealColumn get thighCm => real().nullable()();
  RealColumn get armCm => real().nullable()();
  RealColumn get neckCm => real().nullable()();      // optional
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Sync-Felder (siehe §9)
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

## 5.3 Neue Tabelle: `NutritionLogs`

```dart
class NutritionLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();        // Zeitstempel des Eintrags
  DateTimeColumn get loggedFor => dateTime()();       // welcher Tag/Mahlzeit (00:00 des Tages)
  TextColumn get mealTypeId => text()
      .references(MealTypes, #id, onDelete: KeyAction.restrict)();

  // Quelle: genau eines von drei
  TextColumn get itemId => text().nullable()
      .references(Items, #id, onDelete: KeyAction.setNull)();
  TextColumn get recipeId => text().nullable()
      .references(Recipes, #id, onDelete: KeyAction.setNull)();
  TextColumn get standardMealId => text().nullable()
      .references(StandardMeals, #id, onDelete: KeyAction.setNull)();

  // Portionierung
  RealColumn get servingGrams => real().nullable()();    // z.B. 80g
  RealColumn get servingCount => real().nullable()();    // z.B. 1.5 Portionen

  // Berechnete (oder manuelle) Werte – immer gespeichert für historische Genauigkeit
  RealColumn get calories => real()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get sugarsG => real().nullable()();
  RealColumn get saltG => real().nullable()();

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get modifiedAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}
```

## 5.4 Neue Tabelle: `WaterLogs`

```dart
class WaterLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get loggedAt => dateTime()();
  DateTimeColumn get loggedFor => dateTime()();      // Tag (00:00)
  IntColumn get amountMl => integer()();
  // Sync-Felder ...
}
```

## 5.5 Neue Tabellen: Fitness

```dart
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();    // chest|back|legs|shoulders|arms|core|cardio
  TextColumn get equipment => text().nullable()();   // barbell|dumbbell|machine|bodyweight
  TextColumn get muscleGroups => text().nullable()(); // JSON-Liste primärer Muskelgruppen
  TextColumn get notes => text().nullable()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override Set<Column> get primaryKey => {id};
}

class Workouts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();   // z.B. "Push Day"
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationMinutes => integer().nullable()();
  TextColumn get notes => text().nullable()();
  // Sync-Felder ...
}

class WorkoutSets extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId => text()
      .references(Workouts, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text()
      .references(Exercises, #id, onDelete: KeyAction.restrict)();
  IntColumn get setNumber => integer()();
  IntColumn get reps => integer().nullable()();         // null bei Cardio
  RealColumn get weightKg => real().nullable()();
  IntColumn get durationSeconds => integer().nullable()(); // bei Cardio
  RealColumn get distanceKm => real().nullable()();        // bei Lauf/Rad
  RealColumn get rpe => real().nullable()();   // Rate of Perceived Exertion 1–10
  TextColumn get notes => text().nullable()();
}
```

**Seed:** ~50 Standard-Übungen (Bankdrücken, Kniebeuge, Kreuzheben, Klimmzug, Schulterdrücken, Bizepscurl, Trizepsdrücken, Lat-Zug, Rudern, Beinpresse, Wadenheben, Plank, Crunches, Laufband, Ergometer …).

## 5.6 Neue Tabelle: `BodyPhotos`

```dart
class BodyPhotos extends Table {
  TextColumn get id => text()();
  DateTimeColumn get takenAt => dateTime()();
  TextColumn get photoType => text()();    // front|side|back|face|other
  TextColumn get filePathRelative => text()();  // photos/private/<uuid>.enc
  TextColumn get encryptionIv => text()();      // pro Datei eigener IV (base64)
  IntColumn get fileSizeBytes => integer()();
  RealColumn get weightAtPhotoKg => real().nullable()();  // Snapshot
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

## 5.7 Neue Tabelle: `UserProfile` (Singleton)

```dart
class UserProfile extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();   // immer 1
  TextColumn get displayName => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get sex => text().nullable()();   // male|female|diverse
  RealColumn get heightCm => real().nullable()();
  RealColumn get activityLevel => real().withDefault(const Constant(1.4))(); // PAL
  RealColumn get targetWeightKg => real().nullable()();
  RealColumn get startWeightKg => real().nullable()();
  IntColumn get dailyCalorieGoal => integer().nullable()();
  IntColumn get dailyWaterGoalMl => integer().withDefault(const Constant(2000))();
  TextColumn get dietPlan => text().nullable()();   // keto|mediterranean|if|highprotein|lowcarb|balanced|custom
  RealColumn get proteinTargetG => real().nullable()();
  RealColumn get carbsTargetG => real().nullable()();
  RealColumn get fatTargetG => real().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

---

# 6. Berechnungen (Formeln)

| Wert | Formel |
|------|--------|
| **BMR** (Mifflin-St Jeor) | Männer: `10·kg + 6.25·cm − 5·alter + 5` · Frauen: `… − 161` |
| **TDEE** | `BMR · activityLevel` (1.2 sitzend / 1.4 leicht / 1.55 mittel / 1.75 stark / 1.9 extrem) |
| **Kalorienziel** | `TDEE − Defizit` (Default 500 kcal Defizit) |
| **BMI** | `kg / (m·m)` |
| **Mahlzeit-Kalorien** | `(item.caloriesPer100g · servingGrams / 100)` oder `recipe.caloriesPerServing · servingCount` |

---

# 7. Privater Foto-Bereich (sicherheitskritisch)

## 7.1 Speicherort

```
<vault>/photos/private/<uuid>.enc       ← AES-256-GCM verschlüsselt
<vault>/photos/private/.nomedia         ← blockiert Android MediaScanner
```

Auf Android **zusätzlich** App-internes Verzeichnis nutzen (`getApplicationDocumentsDirectory()`), nicht den Vault-Pfad direkt – damit die Fotos auch bei externer Vault-Lokation sicher in der App-Sandbox liegen. Vault behält nur eine Referenz / Metadaten in der DB.

> **Trade-off:** wenn Fotos zwingend im Vault liegen müssen (für Backup-Portabilität), dann Vault-Pfad nutzen + AES-Verschlüsselung. Dieses Konzept favorisiert die Vault-Variante mit Verschlüsselung, weil "Backup = Ordner kopieren" ein Kernprinzip von LifeOS ist.

## 7.2 Verschlüsselung

- Algorithmus: **AES-256-GCM** (`cryptography` package, schon in pubspec)
- Schlüssel: separater **Photo-Key** wird beim ersten Foto generiert und mit dem Vault-Master-Key per Key-Wrapping geschützt; gespeichert in `flutter_secure_storage`
- Pro Datei eigener **IV** (Initialization Vector), in `body_photos.encryptionIv` abgelegt
- Bei Anzeige: Datei dekrypten in Memory → an Image.memory() reichen → niemals als Klartext-File schreiben

## 7.3 Zugriff

- `local_auth` Biometrie/PIN beim Öffnen des "Ich"-Tabs
- Auto-Lock nach 60 s Inaktivität
- Bei System-Backgrounding: Tab maskieren (überlappendes Sicht-Overlay)
- `android:allowBackup="false"` für die App – verhindert ADB-Backup-Extraktion

## 7.4 Anti-Indexing

- `.nomedia` im Foto-Verzeichnis
- `MediaStore.scanFile` **nicht** aufrufen
- Kein `share_plus` aus dem privaten Bereich (oder nur mit explizitem Hinweis)

---

# 8. Waagen-Eingabe-Flow

Da viele smarte Waagen Bluetooth/proprietäre Apps nutzen, im MVP **manuelle Eingabe** mit allen Feldern auf einem Screen:

```
┌─ Wiegen ─────────────────────┐
│ Datum / Uhrzeit:  [heute]    │
│ Gewicht:          [   ] kg   │
│ Körperfett:       [   ] %    │
│ Muskelmasse:      [   ] %    │
│ Viszeralfett:     [   ]      │
│ Wasseranteil:     [   ] %    │
│            [Speichern]        │
└──────────────────────────────┘
```

**Bluetooth-Waagen:** explizit **nicht im Scope**. Mi Body Scale, Renpho & Co. nutzen proprietäre BLE-Protokolle, Reverse-Engineered Libraries sind instabil und modellspezifisch – das wäre ein eigenes Mini-Projekt. Stattdessen: manuelle Eingabe sauber machen. Falls langfristig gewünscht, eigenes Konzept-Dokument erforderlich.

---

# 9. Sync-Architektur (Phase 5 konkretisiert)

Übernommen vom Sister-Projekt `pomtechflow_mobile`:

| Komponente | Wahl |
|---|---|
| HTTP-Server | `shelf` + `shelf_router`, Port 8765 (oder zufällig) |
| Discovery | `bonsoir` mDNS, Service-Type `_lifeos._tcp` |
| Auth | JWT (HMAC-SHA256), 3 Token-Typen |
| Pairing | QR-Code + 6-stelliger PIN, 5 Min TTL |
| Access-Token | 24h TTL |
| Refresh-Token | 7d TTL |
| Konfliktlösung | **Hybrid je Datentyp** (siehe §9.1) |
| Datenformat | JSON: `{tables: {...}, deletions: [...]}` |
| Verschlüsselung in-transit | LAN-only, kein TLS (akzeptiert wegen Heim-Netz) |
| Token-Storage | `flutter_secure_storage` |

**Endpoints:**
```
GET  /health                       # public
POST /api/pairing/claim            # PIN → Access+Refresh
POST /api/pairing/refresh          # Refresh → neuer Access
GET  /api/v1/sync?since=<iso>      # Pull
POST /api/v1/sync/push             # Push
```

**Anpassungen für LifeOS:** Foto-Dateien werden **nicht** synchronisiert (privat, lokal). Nur DB-Tabellen + Metadaten. Wer Fotos auf zwei Geräten will, kopiert manuell (oder Phase 8: optionaler Foto-Sync mit Re-Encryption pro Gerät).

> **Sicherheits-Memo:** PSK-Pairing (siehe Memory `lifeos_phase5_sync_auth.md`) ist hiermit erfüllt – das JWT-Pairing entspricht der PSK-Anforderung "muss von Tag 1 an sicher sein".

## 9.1 Konfliktauflösung pro Datentyp

Statt globalem LWW wird je nach Datencharakter unterschiedlich vorgegangen:

| Datentyp | Strategie | Konflikt-Möglichkeit | Begründung |
|---|---|---|---|
| **Append-Only Logs** (`NutritionLogs`, `WorkoutSets`, `WaterLogs`, `BodyWeightLogs`, `BodyMeasurements`, `ItemEvents`) | **Konfliktfrei** – beide Einträge bleiben | nie | Mehrere Einträge zur selben Zeit sind kein Konflikt, sondern legitime parallele Logs. |
| **Stammdaten** (`Items`, `Recipes`, `Exercises`, `StandardMeals`, `MealTypes`, `Locations`, `Shops`, `Units`) | **LWW** über `modifiedAt`, ohne Dialog | selten | Bei realer Nutzung kaum gleichzeitig editiert. Verlust akzeptabel. |
| **Singletons / Ziele** (`UserProfile`, `AppSettings`) | **LWW + Konflikt-Dialog**, falls beide Seiten seit letztem Sync geändert | möglich | Hier können Konflikte echte Datenverluste bedeuten (z.B. Kalorienziel). User entscheidet manuell. |
| **Mutable Listen-Items** (`InventoryEntries`, `Tasks`, `WishListEntries`) | **LWW** über `modifiedAt`, ohne Dialog | gelegentlich | Hauptnutzung Mobile, Desktop selten. Verlust einzelner Edits akzeptabel. |

**Konflikt-Dialog-UX (für Singletons):**
```
Konflikt erkannt: Profil
─────────────────────────
Lokal (15:32):    Kalorienziel = 2200 kcal
Vom Server:       Kalorienziel = 2000 kcal
[Lokal behalten] [Server übernehmen] [Beide ansehen]
```

**Implementierung:** in der zentralen `SyncService` wird pro Tabelle eine `conflictPolicy` registriert (`appendOnly | lww | lwwWithDialog`). Append-only-Tabellen werden simpel via `INSERT ... ON CONFLICT IGNORE` gemerged, LWW vergleicht `modifiedAt`, lwwWithDialog ruft einen Conflict-Resolver-Callback in der UI auf.

**Praxisrelevanz:** da der User primär Mobile loggt und Desktop nur als Backup-Server fungiert, sind Konflikte sehr selten. Der Mechanismus ist Versicherung, kein Hauptpfad.

---

# 10. Phasen & Reihenfolge

| Phase | Inhalt | Aufwand (grob) |
|---|---|---|
| **6.1** | "Ich"-Tab-Skeleton + Profil + Gewicht-Erweiterung (KFA, Muskelmasse, Visceral) + Charts (`fl_chart`) + Tracking-Anzeige | 1-2 Tage |
| **6.2** | Körpermaße-Tabelle + Eingabe + Trend-Diagramm | 0.5 Tage |
| **6.3** | OpenFoodFacts-Suche im Item-Dialog + manuell hinzufügen | 0.5 Tage |
| **6.4** | NutritionLogs + Tagebuch-Screen + Mahlzeiten-Slots + Add-Sheet | 2-3 Tage |
| **6.5** | WaterLogs + Wasser-Tracking-Widget | 0.5 Tage |
| **6.6** | UserProfile + Kalorienziel-Berechnung + Tages-Summary mit Donut | 1 Tag |
| **6.7** | Privater Foto-Bereich (Verschlüsselung, App-Lock, Galerie, Vorher/Nachher-Slider) | 2 Tage |
| **6.8** | Fitness-Modul (Exercises-Seed, Workouts, Sets, Logger-UI) | 3-4 Tage |
| **6.9** | Diätplan-Templates (Keto/Mediterran/IF/HighProtein/LowCarb/Ausgewogen) + Mahlzeiten-Voraus-Planung | 2 Tage |
| **5.x** | Sync-Server (pomtechflow-Pattern) inkl. Health-Tabellen | 3-4 Tage |
| ~~6.10~~ | ~~Bluetooth-Waage, Foto-AI-Erkennung~~ | **gestrichen** – manuelle Eingabe genügt; Foto-AI nur sinnvoll am PC und löst kein reales Problem |

**Gesamt MVP Health (6.1–6.6):** ca. **5-7 Tage**, dann ist das Modul FatSecret-vergleichbar nutzbar.

---

# 11. Getroffene Entscheidungen

- [x] **Foto-Speicherort:** Vault + AES-Verschlüsselung (Backup-Portabilität wichtig).
- [x] **Mahlzeiten-Slots:** bestehende `MealTypes`-Tabelle nutzen, mit Default-Seed (Frühstück/Mittag/Abend/Snack/Custom-1/Custom-2).
- [x] **Kalorienziel-Logik:** TDEE-Vorschlag berechnen, Override durch User möglich.
- [x] **Tracking-Anzeige (statt Streak):** monatliche Erfassungsquote + dezenter Wochen-Indikator, **kein** Penalty-Reset. Mild motivierend, abschaltbar.
- [x] **AppLock:** vorerst **nur** "Ich"-Tab schützt sich (vor allem Fotos). App-weiter Lock später als Setting verfügbar, aktuell nicht nötig.
- [x] **Bluetooth-Waagen:** **gestrichen**. Manuelle Eingabe.
- [x] **Foto-AI-Erkennung:** **gestrichen**. Würde nur am PC sinnvoll funktionieren und löst kein reales Problem.
- [x] **Fitness-Sync (Google Fit/Samsung Health/Fitbit):** **nicht in V1**. Separates Konzept-Dokument bei Bedarf.
- [x] **Sync-Strategie:** hybrid pro Datentyp (siehe §9.1) – Logs append-only, Singletons mit Konflikt-Dialog.
- [x] **Modulare Architektur:** Health unter `lib/health/` gekapselt; weitere Module (Bookmarks, FAQs, Haushaltstipps) folgen demselben Muster (siehe §1.1).

---

# 12. Auswirkungen auf das Hauptkonzept

Das Hauptdokument [Projektkonzept - Local-First Household & Life Management System.md](Projektkonzept%20-%20Local-First%20Household%20%26%20Life%20Management%20System.md) muss in folgenden Punkten aktualisiert werden:

1. **Abschnitt 1 "Ziel des Systems"** → Ergänzung "Persönliches Health-Tracking"
2. **Abschnitt 4 Core-System** → neuer Punkt 4.7 "Health-Modul"
3. **MVP-Phasen-Tabelle** → Phase 6 neu, Phase 5 Sync mit konkretem Pattern
4. **Vault-Struktur** → `photos/private/` ergänzen mit Verschlüsselungshinweis

Diese Änderungen werden erst nach Review/Freigabe dieses Konzepts ins Hauptdokument übernommen.
