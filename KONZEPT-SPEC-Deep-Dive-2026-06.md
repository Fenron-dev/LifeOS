# Konzept-Spec: Deep-Dive-Befund & Roadmap (Juni 2026)

Vollständiger Projekt-Audit von LifeOS: Sicherheit, Architektur, Workflows, Tests, Feature-Lücken.
Basis: 135 Dart-Dateien, ~50.000 Zeilen Code (ohne Generate), Schema v41, 8 Test-Dateien (~830 Zeilen).

**Verwandte Dokumente:** [Tiefenscan-Backlog Mai 2026] (Memory), GitHub Issues #1–#15.

---

## Teil 1 — Sicherheit 🔴

### S1 · Sync läuft unverschlüsselt über HTTP (KRITISCH)

`lib/services/sync_server.dart` + `sync_client.dart`: Der gesamte Sync-Verkehr — inklusive
PSK als `Authorization: Bearer <psk>` — geht im Klartext über das WLAN. Jeder Mitleser im
Netz (offenes WLAN, kompromittierter Router, anderes Gerät) kann die PSK abgreifen und
danach beliebig Events lesen/schreiben.

**Fix-Optionen (aufsteigende Komplexität):**
1. **HMAC-Signierung statt Bearer-Token:** Client signiert `timestamp + body` mit der PSK
   (HMAC-SHA256), Server verifiziert + Replay-Schutz über Timestamp-Fenster. PSK verlässt
   nie das Gerät. Empfohlener erster Schritt.
2. **Selbstsigniertes TLS:** Server generiert beim ersten Start ein Zertifikat, Client pinnt
   den Fingerprint beim Pairing (Trust on First Use). `shelf` unterstützt `SecurityContext`.
3. Kombination aus beidem.

### S2 · PSK liegt im Klartext in SharedPreferences (HOCH)

`lib/providers/sync_provider.dart` speichert `_kServerPsk` / `_kClientPsk` via
`SharedPreferences` — Klartext auf der Platte. Der Doc-Kommentar in `sync_server.dart`
behauptet „stored in secure storage". `SecretStorage` (Keychain/Keystore/libsecret)
existiert bereits im Projekt und muss hier verwendet werden.

### S3 · Kein Brute-Force-Schutz am Sync-Server (MITTEL)

PSK = 8 Zeichen aus 32er-Alphabet ≈ 40 bit Entropie. Ohne Rate-Limiting ist das auf
LAN-Geschwindigkeit brute-forcebar. **Fix:** Fehlversuchszähler pro IP mit exponentiellem
Backoff (z. B. nach 5 Fehlversuchen 30 s Sperre), optional PSK auf 12+ Zeichen verlängern.

### S4 · PSK-Vergleich nicht constant-time (MITTEL)

`token != psk` in `_pskMiddleware` erlaubt theoretisch Timing-Angriffe.
**Fix:** Konstante-Zeit-Vergleichsfunktion (XOR-Fold über beide Strings fixer Länge).

### S5 · Event-Log via Sync überschreibbar (MITTEL)

`insertSyncedEvents()` nutzt `insertAllOnConflictUpdate` — ein Client kann damit
**bestehende Events anderer Geräte überschreiben** (gleiche Event-ID → Update). Das
Event-Log ist konzeptionell append-only/immutabel.
**Fix:** `InsertMode.insertOrIgnore` — existierende IDs werden still übersprungen.

### S6 · Kein Body-Size-Limit auf POST /events (MITTEL)

Ein 2-GB-Body wird komplett in den Speicher gelesen (`req.readAsString()`) → DoS.
**Fix:** `Content-Length` prüfen, Limit z. B. 10 MB, sonst 413.

### S7 · Body-Foto-Key gerätegebunden und vault-übergreifend (NIEDRIG)

`PhotoEncryptionService` legt EINEN globalen Key in Secure Storage (`lifeos_photo_key_v1`):
- **Vault-Portabilität gebrochen:** Vault-Ordner auf neuen Rechner kopieren → Fotos
  unentschlüsselbar (Key bleibt auf altem Gerät). Widerspricht dem Kernkonzept
  „Backup = Ordner kopieren".
- Alle Vaults teilen denselben Key.

**Fix:** Key pro Vault ableiten/ablegen — z. B. wrapped Key in `vault.json` (verschlüsselt
mit dem Vault-Key) oder Ableitung aus dem SQLCipher-Key via HKDF.

### S8 · Sonstiges (NIEDRIG/INFO)

- `/api/v1/ping` ist unauthentifiziert und leakt die `deviceId` (UUID). Akzeptabel, aber
  dokumentieren.
- Mealie-Token darf über HTTP gesendet werden (bewusste LAN-Entscheidung) — der bestehende
  Warnhinweis ist ok, sollte aber beim Speichern der Config erneut erscheinen.
- Backup-ZIP enthält `cache/` (Thumbnails, laut Konzept „disposable, no backup needed")
  und `exports/` (alte Backups → Backup-im-Backup). Beide Ordner ausschließen.

---

## Teil 2 — Funktionale Defekte im Sync 🟠

Diese Punkte machen den Phase-5-Sync aktuell **funktionsunfähig** und gehören zu
GitHub-Issue #1 („Server Client Synchronisation"):

### F1 · Events werden nach Push nie als `synced` markiert

`SyncOpsNotifier.sync()` filtert auf `syncStatus != 'synced'`, aber nach erfolgreichem
Push wird der Status lokal nie aktualisiert → **jeder Sync überträgt alle Events erneut.**
**Fix:** Nach `pushEvents()` ein `UPDATE item_events SET sync_status='synced',
synced_at=? WHERE id IN (...)` in einer Transaktion.

### F2 · `item_states` wird nach Pull nie neu berechnet

Gepullte Events landen in `item_events`, aber die materialisierte Projektion
(`item_states`) bleibt unverändert → **der Bestand auf dem Zielgerät ändert sich nicht.**
Der Sync ist damit für den Nutzer wirkungslos.
**Fix:** Projektion-Rebuild nach Pull (siehe F4).

### F3 · Nur Events syncen — Stammdaten nicht

`items`, `recipes`, `locations`, `shops`, `item_groups`, … werden nicht übertragen.
Legt Android einen neuen Artikel an und kauft ihn, erhält der Desktop ein Event mit
unbekannter `item_id` → verwaistes Event.
**Fix (Konzept):** Zweiter Sync-Kanal für Stammdaten mit Last-Write-Wins auf
`updated_at`-Basis: `GET/POST /api/v1/entities?since=…` mit Tabellen-Whitelist.
Reihenfolge beim Pull: Stammdaten zuerst, dann Events.

### F4 · Keine Projektion-Rebuild-Funktion vorhanden

CLAUDE.md verspricht: „`item_states` ist always recomputable from events" — es gibt
aber **keinen Code**, der das tut.
**Fix:** `rebuildItemStates({Set<String>? itemIds})` in `database.dart`:
Events je Item chronologisch falten (purchase → +qty, consumption → −qty,
state_change → state, …) und `item_states` ersetzen. Wird gebraucht von: Sync-Pull (F2),
Reparatur-Funktion in Settings („Bestand neu berechnen"), Tests.

---

## Teil 3 — Architektur & Code-Qualität 🟡

### A1 · i18n ist de facto tot — Entscheidung nötig

Nur **4** `AppLocalizations.of(...)`-Aufrufe im gesamten Code, dagegen **428+**
hartkodierte deutsche UI-Strings — obwohl CLAUDE.md l10n vorschreibt und
`app_en.arb` gepflegt aussieht. Zwei ehrliche Optionen:

- **Option A (empfohlen bei Solo-Nutzung):** Deutsch als einzige Sprache festschreiben,
  ARB-Dateien + Sprachumschalter entfernen, CLAUDE.md-Regel streichen. Spart Pflege.
- **Option B:** Migrations-Sprint — alle Strings in ARB überführen (~2–3 Tage Arbeit,
  mechanisch). Nur sinnvoll, wenn Mehrsprachigkeit wirklich geplant ist.

Der aktuelle Zustand (halb/halb) ist der schlechteste: Der EN-Locale-Schalter in den
Settings erzeugt eine App, die zu 95 % trotzdem Deutsch ist.

### A2 · Monster-Dateien aufteilen

| Datei | Zeilen | Vorschlag |
|---|---|---|
| `item_detail_screen.dart` | 3.888 | Sections in eigene Dateien (`item_detail/` Ordner): Stock, PriceHistory, Events, Nutrition, Sheets |
| `workouts_tab.dart` | 3.442 | Pro Screen eine Datei: ActiveWorkout, PlanDetail, ExerciseDetail, Library |
| `database.dart` | 3.016 | **DAOs einführen** — CLAUDE.md verspricht `lib/db/daos/` (items, events, recipes, tasks, health, sync), existiert aber nicht |

### A3 · Automation-Engine hat keine Trigger

If→Then-Regeln (`automation_provider.dart`) laufen **nur manuell** über den
Settings-Screen („Jetzt ausführen"). Es gibt keinen Trigger-Mechanismus.
Zusätzlich: Die `notify`-Action gibt nur einen String zurück, sendet keine echte
Notification.

**Fix-Konzept:** `AutomationTriggerService` als Riverpod-Side-Effect-Provider (analog
`expiryNotificationSchedulerProvider`): lauscht auf Event-Streams (Item-Events,
Zeitplan via Timer) und wertet `rule.trigger` (JSON) gegen die Änderung aus.
Trigger-Typen v1: `on_low_stock`, `on_expiry_within`, `on_purchase`, `daily_at`.
`notify`-Action an `NotificationService.show()` anbinden.

### A4 · Desktop-Versprechen unvollständig

CLAUDE.md/Konzept nennen für Desktop: „MenuBar + keyboard shortcuts". Im
`adaptive_shell.dart` existiert **kein einziger Shortcut** (kein `Shortcuts`/
`SingleActivator`). Minimal-Set: `Cmd/Ctrl+F` Suche, `Cmd/Ctrl+N` neuer Artikel,
`Cmd/Ctrl+1..5` Tab-Wechsel, `Esc` Detail schließen.

### A5 · Kleinere Punkte

- `flutter_secure_storage` 10.0.0 → 10.3.1, `sqlcipher_flutter_libs` ist EOL-markiert
  (`0.7.0+eol`) → Migrationspfad für SQLCipher-Bezugsquelle klären (Drift empfiehlt
  inzwischen `sqlite3_flutter_libs` + eigene Cipher-Einbindung oder Fork).
- 73 Pakete mit neueren Major-Versionen — geplanter Dependency-Sprint (riverpod 3,
  go_router 17, fl_chart 1.x, flutter_local_notifications 22) statt ewigem Aufschieben.
- `home_widget`-Updater läuft auch auf Desktop durch (`homeWidgetUpdaterProvider`
  watcht Streams, `HomeWidgetService.update()` bricht erst innen ab) — Provider sollte
  auf Android-only gegated werden, spart Stream-Subscriptions.

---

## Teil 4 — Tests & CI/CD 🟡

### T1 · Testabdeckung < 2 %

831 Zeilen Tests für ~50.000 Zeilen Code. Ungetestet sind ausgerechnet die
riskantesten Pfade:

**Prioritäre Test-Kandidaten (reine Dart-Logik, ohne UI):**
1. Event-Sourcing: purchase/consume/stocktake → erwarteter `item_states`-Stand
   (inkl. künftigem `rebuildItemStates`)
2. Sync: `eventToJson`/`jsonToCompanion` Roundtrip, Push-Filter, Pull-Cursor,
   PSK-Middleware (401, Bearer-Parsing)
3. `VaultKeyService`: PBKDF2-Determinismus, Salt-Handling, Keystore-Roundtrip
4. `AllergenDetector`, `ExpiryDateOcr._extractBestDate` (Datums-Parsing-Matrix)
5. `BackupService.restoreBackup` Zip-Slip-Abwehr (bösartige Pfade)

### T2 · Kein Release-Workflow

CI baut nur **Debug**-Artifacts mit 3 Tagen Retention. Es fehlt ein
`release.yml` (Trigger: Git-Tag `v*`):
- Android: signiertes APK/AAB
- Linux: Release-Bundle als tar.gz (+ optional AppImage/Flatpak)
- macOS: Release-.app als DMG/ZIP (Codesigning/Notarization später)
- Windows: Release-Ordner als ZIP (+ optional MSIX/Inno-Setup)
- GitHub Release mit allen Artefakten + Changelog aus Commits

### T3 · CI-Feinheiten

- Desktop-Jobs bauen Debug — Release-only-Fehler (z. B. tree-shake-icons,
  AOT-Probleme) bleiben unbemerkt. Mindestens einen Release-Build pro Plattform
  nightly oder pro Tag.
- `flutter analyze --fatal-infos` läuft nur auf Ubuntu — reicht, aber Drift-Codegen
  (`build_runner`) läuft 5× redundant. Caching des `.dart_tool/build`-Outputs
  zwischen Jobs via `actions/cache` spart ~2 Min/Job.

---

## Teil 5 — Workflow-Optimierungen (UX) 🟢

1. **Sync-Pairing per QR-Code:** Desktop zeigt QR (`lifeos-sync://<ip>:<port>?psk=<psk>`),
   Android scannt mit vorhandenem `mobile_scanner` → entfällt IP+PSK abtippen.
2. **mDNS/Bonjour-Discovery:** Desktop announced `_lifeos._tcp`, Android findet den
   Server automatisch (`multicast_dns`-Package). QR bleibt Fallback.
3. **Auto-Sync:** Beim App-Start und danach alle N Minuten im Hintergrund syncen
   (wenn Server erreichbar), statt nur manuell. Status-Indikator in der AppBar
   (zuletzt synchronisiert / Fehler).
4. **Meal-Plan → Einkaufsliste:** Wochenplan vorhanden, aber fehlende Zutaten der
   geplanten Rezepte landen nicht automatisch auf der Einkaufsliste. Ein Button
   „Fehlendes für diese Woche" schließt die Lücke Einkauf↔Kochen.
5. **Abfall-Auswertung:** `consumptionReason == 'expired'/'spoiled'` wird erfasst,
   aber nirgends ausgewertet. Dashboard-Karte „Weggeworfen diesen Monat (€)" —
   starker Anreiz, das MHD-System zu nutzen.
6. **Onboarding-Reparatur-Tools:** Settings-Eintrag „Bestand neu berechnen"
   (nutzt `rebuildItemStates` aus F4) + „Datenbank-Integritätscheck" (PRAGMA
   integrity_check) für Selbsthilfe bei Inkonsistenzen.
7. **Fenster-Persistenz Desktop:** Fenstergröße/-position beim Beenden speichern
   (`window_manager`-Package), statt immer 1280×720.

---

## Teil 6 — Neue Feature-Ideen (bewertet) 🟢

| Feature | Nutzen | Aufwand | Prio |
|---|---|---|---|
| QR-Pairing für Sync (5.1) | Hoch | Klein | P1 |
| Auto-Sync + Statusanzeige (5.3) | Hoch | Klein | P1 |
| Meal-Plan → Einkaufsliste (5.4) | Hoch | Mittel | P1 |
| Abfall-/Kosten-Auswertung (5.5) | Mittel | Klein | P2 |
| mDNS-Discovery (5.2) | Mittel | Mittel | P2 |
| CSV-Import (Artikel-Massenimport beim Einzug) | Mittel | Mittel | P2 |
| Rezept-Foto via OCR → Zutatenliste | Mittel | Groß | P3 |
| Etiketten-Druck (QR je Lagerort/Behälter) | Nische | Mittel | P3 |
| Preis-Alarm (Artikel unter Durchschnittspreis) | Nische | Klein | P3 |
| Haushaltsbuch-Export (Steuern/Budget, DATEV-CSV) | Nische | Mittel | P4 |

Bereits als GitHub-Issues erfasst (nicht doppeln): EAN-Prüfsumme (#3),
Force-Unwrap-Fix (#4), Provider-Invalidierung (#5), DB-Indizes (#6), SQL-Sort (#7),
healthFactor-Formularfeld (#8), Vault-Wechsel-UI (#9), Foto-MIME-Validierung (#10),
Schnell-Auffüllen (#11), macOS-Verifikation (#12/#13), CI-Verifikation (#14),
SPRINT_E.md-Doku (#15).

---

## Teil 6b — Einheiten-System & Bestandsbuchung (Nutzer-Befund Juni 2026) 🔴

> Symptom (vom Nutzer gemeldet): „Kaufe Stück/Packung, verbrauche in Gramm. Beim
> Tagebuch-Eintrag wird viel zu viel ausgebucht, obwohl die Mengen im Gericht stimmen."
> Zweites Symptom: „Einkauf erfassen dauert ewig → ich mache es nicht mehr."

### U1 · Kernbug: Angeforderte Menge wird bei der Ausbuch-Vorbelegung ignoriert

`inventory_deduct_sheet.dart` → `makeRow()`: Die Tagebuch-/Rezeptmenge (z. B. 125 g)
wird **nie über die Umrechnungstabelle in die Bestandseinheit konvertiert**. Stattdessen
läuft `_heuristicQty()`:

- Bestandseinheit „Stück"/„Packung" (kein Gewicht) + `servingSizeG == null`
  → Fallback = **1.0**, egal ob 10 g oder 400 g geloggt wurden.
- In `buildDeductUnitOptions(diaryMode: true)` wird daraus `defaultQty = fallback / factor`.
  Beispiel: Bestand „Stück", Umrechnung 1 Stück = 500 g, `consumeUnit = 'g'`
  → vorbelegt werden `1.0 / (1/500)` = **500 g** — statt der geloggten 125 g!

Das ist exakt das gemeldete „viel zu viel". Besonders tückisch: Die korrekte Zahl
steht als Text daneben („Tagebuch: 125 g"), fließt aber nicht in die Vorbelegung ein.
Die passende Hilfsfunktion `unitToGrams()` existiert in `unit_deduct_utils.dart`,
wird im Deduct-Flow aber **nirgends aufgerufen**.

**Fix:** Vorbelegung = angeforderte Menge, konvertiert in die gewählte Options-Einheit:
`prefill(option) = requestedQty × gramsPerRequestedUnit / gramsPerOptionUnit`
(via `unitToGrams(unit, conversions)`; Fallback auf Heuristik nur wenn keine
Umrechnungskette existiert — dann aber mit deutlicher Warnung in der UI statt
stiller Falschbuchung).

### U2 · `_computeServings` ignoriert Stück-Zutaten

Bei Gerichten wird das Gesamtgewicht pro Portion nur über `convertWeightVol` summiert —
Zutaten in „Stück" (Eier!) fallen still aus der Summe. Beispiel: Gericht = 2 Eier +
100 g Mehl → Systemgewicht 100 g statt ~220 g → geloggte 200 g ⇒ „2 Portionen"
statt 0,9 ⇒ **alle Zutaten doppelt ausgebucht**.
**Fix:** `unitToGrams(ing.unit, conversions)` statt nur `convertWeightVol` verwenden.

### U3 · Rezept-Kochen bucht komplett ohne Umrechnung aus (schwerster Fall)

`recipe_detail_screen.dart` → `_CookRecipeSheet._cook()`:
`needed = ing.quantity * _scale` wird **direkt** gegen `entry.quantity` gebucht —
Gramm gegen Stück, ohne jede Konvertierung. Zutat „125 g", Bestand „2 Stück (à 500 g)"
→ es werden 125 „Stück-Einheiten" abgezogen = Bestand komplett vernichtet.
**Fix:** Gleiche Konvertierungsroutine wie U1 vor der FIFO-Schleife; Einheiten-Mismatch
ohne Umrechnungsweg → Zeile im Sheet markieren statt still falsch buchen.

### U4 · Datenmodell: drei konkurrierende Mechanismen, keiner vollständig

| Mechanismus | Zweck heute | Problem |
|---|---|---|
| `purchaseUnit`/`purchaseQty` (Item) | Nur Packungsanzahl in der Einkaufsliste | Fließt NICHT in Umrechnungen ein |
| `consumeQty`/`consumeUnit` (Item) | Default im Deduct-Sheet | Nur Vorauswahl, keine Mengenlogik |
| `unit_conversions` (global + je Item) | Generische Faktoren | Muss manuell je Artikel gepflegt werden |

Der Nutzer-Wunsch „pro Artikel hinterlegen: Kaufeinheit + Inhalt" braucht **eine**
zentrale Stelle:

**Konzept „Packungs-Definition am Artikel":**
```
Item:
  purchaseUnit        = 'Packung'   (existiert)
  packageContentQty   = 500         (NEU)
  packageContentUnit  = 'g'         (NEU)
```
- Wirkt als **implizite Item-Umrechnung** `1 Packung = 500 g` in ALLEN
  Konvertierungspfaden (Deduct-Sheet, Rezept-Kochen, Servings-Berechnung,
  Einkaufslisten-Packungsanzahl) — eine zentrale Funktion
  `resolveConversions(item)` liefert implizite + explizite Umrechnungen gemeinsam.
- Artikelformular: ein Block „Ich kaufe in … / Eine Einheit enthält …" ersetzt
  das verstreute Pflegen von unit_conversions je Artikel.
- Beim Einbuchen in `purchaseUnit`, beim Ausbuchen in beliebiger Einheit —
  die Kette Packung→g→kg ist immer auflösbar.
- Migration: bestehende Item-Conversions bleiben gültig (explizit schlägt implizit).

### U5 · Pflicht-Tests für das Einheiten-System

Umrechnungsmatrix als Unit-Tests (g↔kg↔Stück↔Packung↔Portion, mit/ohne Conversion,
diaryMode true/false, Meals mit gemischten Einheiten) — **bevor** die Fixes gebaut
werden, damit die Fälle des Nutzers reproduzierbar abgesichert sind. Das ist die
wichtigste Kernlogik der App und hat heute null Tests.

### U6 · Umsetzungsleitfaden Phase U (Datei für Datei)

**Schritt 0 — Failing Tests (`test/utils/unit_deduct_utils_test.dart`, neu):**
```
unitToGrams:
  'g' → 1.0 · 'kg' → 1000 · 'Stück' + [Stück→g, f=500] → 500
  'Packung' + [g→Packung, f=0.002] → 500 (Reverse-Pfad)
Prefill-Matrix (der gemeldete Fall):
  requested (125, 'g'), Bestand 'Stück', Conv 1 Stück = 500 g
  → Option 'Stück': prefill 0.25 · Option 'g': prefill 125   // heute: 1 bzw. 500!
Servings gemischt:
  Gericht = 2 Eier ('Stück', Conv Ei→60 g) + 100 g Mehl; geloggt 220 g
  → servings ≈ 1.0   // heute: 2.2, weil Eier ignoriert
Rezept-Kochen:
  Zutat (125, 'g'), Entry (2, 'Stück', Conv 500 g)
  → deduct 0.25 Stück   // heute: 125 „Stück"
```

**Schritt 1 — Schema v42 (`lib/db/tables/items_table.dart` + `database.dart`):**
```dart
/// Inhalt einer Kaufeinheit: 1 [purchaseUnit] = packageContentQty [packageContentUnit]
RealColumn get packageContentQty => real().nullable()();
TextColumn get packageContentUnit => text().nullable()();
// Migration: if (from < 42) addColumn ×2 — kein Datenumbau nötig.
```

**Schritt 2 — Zentrale Auflösung (`lib/utils/unit_deduct_utils.dart`):**
```dart
/// Explizite Item-Conversions + implizite Packungs-Conversion + globale — in
/// dieser Prioritätsreihenfolge. EINZIGER Einstiegspunkt für alle Buchungspfade.
List<UnitConversion> resolveConversions({
  required Item? item,
  required List<UnitConversion> itemConvs,
  required List<UnitConversion> globalConvs,
}) {
  final implicit = <UnitConversion>[];
  if (item?.purchaseUnit != null &&
      item?.packageContentQty != null &&
      item?.packageContentUnit != null) {
    implicit.add(/* purchaseUnit → packageContentUnit, factor: packageContentQty */);
  }
  return [...itemConvs, ...implicit, ...globalConvs];
}

/// Konvertiert (qty, from) → to über die Gramm-Brücke. Null = kein Pfad.
double? convertQty(double qty, String from, String to, List<UnitConversion> convs) {
  final fg = unitToGrams(from, convs); final tg = unitToGrams(to, convs);
  if (fg == null || tg == null || tg == 0) return null;
  return qty * fg / tg;
}
```

**Schritt 3 — U1-Fix (`inventory_deduct_sheet.dart` → `makeRow`):**
`buildDeductUnitOptions` bekommt statt `fallbackQty` die Parameter
`requestedQty`/`requestedUnit`; Prefill je Option =
`convertQty(requestedQty, requestedUnit, option.unit, convs)`.
Nur wenn `convertQty` null liefert → alte Heuristik + oranges Warn-Badge
„Einheit nicht umrechenbar — Menge prüfen" an der Zeile.

**Schritt 4 — U2-Fix (`_computeServings`):**
`convertWeightVol(ing.qty, ing.unit, 'g')` ersetzen durch
`ing.qty * (unitToGrams(ing.unit, convsFürZutat) ?? 0)`; Zutaten ohne
Gramm-Pfad zählen weiterhin nicht, werden aber gezählt und als Hinweis
angezeigt („2 Zutaten ohne Gewichtsangabe").

**Schritt 5 — U3-Fix (`recipe_detail_screen.dart` → `_CookRecipeSheet._cook`):**
Vor der FIFO-Schleife: `needed = convertQty(ing.quantity * _scale, ing.unit,
entry.unit, convs)`; null → Zeile im Sheet rot markieren, Checkbox
deaktivieren (statt still falsch buchen). Sheet zeigt je Zeile die
umgerechnete Abbuchung als Vorschau („125 g = 0,25 Pck.").

**Schritt 6 — Formular (`item_form_screen.dart`):**
Block „Einkauf & Inhalt": `Ich kaufe in [Packung ▼] · 1 Packung enthält
[500] [g ▼]` — ersetzt für den Normalfall das manuelle Anlegen von
unit_conversions. Bestehende Conversions bleiben gültig (explizit > implizit).

**Schritt 7 — E1 Kassenbon-Modus (neu `lib/screens/scanner/purchase_session_screen.dart`):**
Scanner-Widget oben (mobile_scanner, `detectionSpeed: normal`, kein Auto-Pop),
Session-Liste darunter (`StateNotifier<List<SessionRow>>`). Scan-Handler:
EAN → Item-Lookup → Zeile hinzufügen/hochzählen (Prefills wie AddStockSheet).
„Alle einbuchen" → `inventoryOps.purchase()` je Zeile in einer Transaktion.
Einstieg: neue Schnellaktion „Einkauf erfassen" + Button in der Einkaufsliste.

---

## Teil 6c — Einkaufserfassung beschleunigen (Nutzer-Befund Juni 2026) 🟠

**Ist-Zustand:** Pro Artikel: Schnellaktion öffnen → „Schnelleinbuchen" → Scanner →
AddStockSheet (Menge, Einheit, Preis, MHD, Lagerort, Shop, Zustand, Behälter) →
Speichern → **Scanner ist zu, von vorn**. Bei 30 Artikeln: 30 × (5–8 Taps + Scan)
≈ 5–10 Minuten reine Bedienarbeit. Konsequenz beim Nutzer: Erfassung unterbleibt →
App-Nutzen kollabiert.

Gute Grundlagen existieren bereits (Location-/MHD-/Einheiten-Prefill, Smart Tara,
OCR) — das Problem ist der **fehlende Batch-Modus**.

### E1 · Kassenbon-Modus (Batch-Scan-Loop) — wichtigste Maßnahme

Neuer Flow „Einkauf erfassen":
1. Scanner bleibt **dauerhaft offen**; jeder Scan piept und legt eine Zeile in einer
   Session-Liste an (Artikel, 1 × purchaseUnit, Default-Lagerort, Auto-MHD aus
   shelfLifeDays). Mehrfach-Scan desselben Artikels ⇒ Menge +1.
2. Unbekannter EAN ⇒ Zeile „Neu anlegen?" (wird ans Ende gestellt, blockiert nicht).
3. Liste unter dem Scanner live sichtbar; Tap auf Zeile öffnet Mini-Editor
   (Menge/Preis/MHD) — optional, nie erzwungen.
4. Ein einziges „Alle einbuchen" am Ende schreibt alle purchase-Events in einer
   Transaktion; Undo-Snackbar.

Ergebnis: 30 Artikel ≈ 30 Scans + 1 Tap statt ~200 Taps.

### E2 · Direktbuchung mit Undo (Einzel-Scan)

Wenn Artikel-Stammdaten vollständig sind (purchaseUnit, Default-Lagerort,
shelfLifeDays), das AddStockSheet **überspringen**: Scan bucht sofort
„1 Packung, MHD auto", SnackBar „Eingebucht — Bearbeiten | Rückgängig".
Als Setting „Direktbuchung" (Standard an, wenn Stammdaten komplett).

### E3 · Einkaufsliste = Einbuch-Vorlage

Nach dem Einkauf: Einkaufsliste öffnen → „Einkauf abschließen" → alle abgehakten
Positionen werden als Batch eingebucht (Menge aus der Liste, Packungsanzahl via U4).
Deckt den Fall „ohne Scanner, Liste war eh gepflegt" ab und verbindet zwei
existierende Welten.

### E4 · Später: Kassenbon-OCR

Foto vom Bon → Zeilenerkennung (ML Kit ist schon eingebunden) → Matching gegen
Artikelnamen/Preise → Vorschlagsliste zum Bestätigen. Größerer Aufwand, erst nach
E1–E3 sinnvoll.

---

## Teil 6d — Feature-Ideen, zweite Runde 🟢

Diese Ideen nutzen fast ausschließlich **Daten, die die App heute schon sammelt**
(Event-Log, Preise, Gewichts-/Ernährungslogs) — hoher Nutzen bei moderatem Aufwand:

| Feature | Beschreibung | Nutzen | Aufwand | Prio |
|---|---|---|---|---|
| **Vorratsreichweite** | Verbrauchsrate aus consumption-Events je Artikel → „Kaffee reicht noch ~12 Tage"; Badge im Inventar, Warnung vor der Einkaufsliste | Hoch | Mittel | P1 |
| **„Was kann ich kochen?"** | Rezepte gegen aktuellen Bestand matchen; Sortierung: ablaufende Zutaten zuerst („Rette dein MHD"). Verbindet Inventar + Rezepte + Abfallvermeidung | Hoch | Mittel | P1 |
| **Mindestbestand lernen** | Vorschlag für minStockQuantity aus Verbrauchsrate × Einkaufsintervall statt manueller Pflege | Hoch | Klein | P1 |
| **TDEE & Gewichtsprognose** | Aus kcal-Logs + Gewichtsverlauf den tatsächlichen Erhaltungsbedarf schätzen; Trendlinie + „Ziel erreicht in ~X Wochen" | Hoch (Health-Ziel) | Mittel | P1 |
| **Auto-Backup** | Zeitgesteuertes ZIP-Backup (täglich/wöchentlich) in wählbaren Ordner, Aufbewahrung N Stück; nutzt vorhandenen BackupService | Hoch | Klein | P1 |
| **Inventur-Modus** | Geführter Rundgang je Lagerort: Bestand bestätigen/korrigieren (nutzt vorhandene stocktake-Events); danach „Bestand geprüft am …" | Mittel | Mittel | P2 |
| **Wochen-Report Health** | Karte/Push So-Abend: Ø kcal, Protein-Zielquote, Gewichts-Delta, Workouts — Motivations-Loop | Mittel | Klein | P2 |
| **Lebensmittel-Budget** | Monatsbudget definieren; Ist aus purchase-Events (Preise existieren); Fortschrittsbalken im Dashboard | Mittel | Klein | P2 |
| **Garantie-Tracking** | `warrantyMonths` an Geräten + Kaufdatum aus Events → Erinnerung vor Ablauf; Rechnung als entity_photo anhängen | Mittel | Klein | P2 |
| **Reste einlagern nach Kochen** | Im Kochen-Sheet: „Reste als Gericht einlagern" → prepared_dishes-Eintrag mit MHD (Tabelle existiert bereits!) | Mittel | Klein | P2 |
| **Android App Shortcuts** | Long-Press aufs Icon → „Einkauf erfassen" / „Tagebuch" / „Scannen" direkt | Klein | Klein | P3 |
| **Daten-Hygiene-Check** | Settings-Tool: Duplikate (gleicher EAN/ähnlicher Name), verwaiste Events, Zutaten ohne Artikel-Link finden | Klein | Klein | P3 |
| **Desktop Drag & Drop** | Fotos/Rechnungen per Drag & Drop auf Artikel ziehen (desktop_drop-Package) | Klein | Klein | P3 |

**Sofort-Kandidaten** (bester Nutzen/Aufwand): Mindestbestand lernen, Auto-Backup,
Wochen-Report, Budget, Reste einlagern — alle „Klein" und auf vorhandenen Daten.

### Integrationspläne (für die spätere Umsetzung)

> Schema-Sequenz: Phase U belegt **v42** (packageContentQty/Unit). Die Features hier
> nutzen **v43** (ein gemeinsamer Bump für alle neuen Spalten dieser Runde:
> `items.warrantyMonths`). Alles andere kommt ohne Schema-Änderung aus.
> Settings-Erweiterungen folgen dem bestehenden Muster in
> `settings_provider.dart` (`AppSettingsData` + SharedPreferences-Keys + Setter).

#### F1 · Vorratsreichweite („reicht noch ~X Tage")

**Datenbasis:** `item_events` mit `type='consumption'` (quantity, unit, createdAt) —
vollständig vorhanden.

1. **`lib/utils/consumption_stats.dart` (neu):**
   ```dart
   /// Verbrauchsrate in Bestandseinheit/Tag über [window] (Default 60 Tage).
   /// Null wenn < 3 consumption-Events im Fenster (zu wenig Signal).
   double? dailyConsumptionRate(List<ItemEvent> events, {Duration window});
   /// Reichweite in Tagen: currentStock / rate. Null wenn rate null/0.
   double? daysOfStockLeft(double currentStock, double? rate);
   ```
2. **DB:** `Future<List<ItemEvent>> consumptionEventsSince(String itemId, DateTime since)`
   — einfacher select auf item_events (Index aus Issue #6 nutzen).
3. **Provider:** `stockReachProvider = FutureProvider.family<double?, String>` —
   kombiniert `itemStockMapProvider` + Events; cachen, nicht streamen (teuer).
4. **UI:** Badge im Inventar-Listitem („~12 T"), Abschnitt im Item-Detail
   (`_StockSection`), Warnfarbe < 7 Tage. Dashboard-Karte „Geht bald aus"
   (Reichweite < 7 T und kein Einkaufslisten-Eintrag) unter der StapleWarningCard.
5. **Tests:** Ratenberechnung mit synthetischen Events (gleichmäßig, Burst, leer).

#### F2 · „Was kann ich kochen?"

**Datenbasis:** `recipe_ingredients.itemId` (nullable Verknüpfung), `item_states`
(Bestand), `inventory_entries.expiryDate`.

1. **DB:** `Future<List<RecipeMatch>> matchRecipesAgainstStock()` in einem neuen
   `lib/db/daos/recipe_match_dao.dart` (erster DAO — Startpunkt für A2):
   je Rezept: verknüpfte Zutaten zählen, davon „auf Lager" (Bestand ≥ benötigte
   Menge via `convertQty` aus Phase U — **Abhängigkeit!**), Anteil berechnen.
   `RecipeMatch(recipe, totalLinked, inStock, missingItems, expiringCount)`.
2. **Ranking:** `expiringCount` desc (MHD ≤ 7 T unter den Zutaten), dann
   `inStock/totalLinked` desc. Rezepte ohne verknüpfte Zutaten ausblenden.
3. **UI:** Neuer Tab/Filter-Chip „Kochbar" im Rezepte-Screen + Dashboard-Karte
   „Rette dein MHD: 3 Rezepte mit ablaufenden Zutaten". Fehlende Zutaten je
   Karte als Chips mit „+ Einkaufsliste"-Aktion (nutzt insertCustomShoppingItem).
4. **Performance:** Ein Query-Durchlauf mit Joins statt N+1; bei > 200 Rezepten
   als FutureProvider mit Pull-to-Refresh statt Stream.

#### F3 · Mindestbestand lernen

**Datenbasis:** wie F1 + `item_events type='purchase'` (Einkaufsintervall).

1. **`consumption_stats.dart`:** `double? suggestedMinStock(rate, avgDaysBetweenPurchases)`
   = Rate × Intervall × 1,2 (20 % Puffer), gerundet auf sinnvolle Schrittweite.
2. **UI (kein Automatismus!):** Im Artikelformular neben dem minStock-Feld ein
   Hinweis-Chip „Vorschlag: 2,5 kg (aus deinem Verbrauch)" → Tap übernimmt.
   Zusätzlich Sammel-Screen unter Einstellungen → „Mindestbestände prüfen":
   Liste aller Items mit Abweichung Vorschlag vs. gesetzt > 50 %, je Zeile
   „Übernehmen".
3. **Kein Schema nötig** — reine Berechnung + bestehendes Feld.

#### F4 · TDEE & Gewichtsprognose

**Datenbasis:** `body_weight_logs` (weightKg, loggedAt), `dailyNutritionTotals`
(kcal/Tag), `user_profile` (targetWeightKg vorhanden in stats_table).

1. **`lib/health/utils/tdee_estimator.dart` (neu):**
   ```dart
   /// TDEE aus Energiebilanz: Ø kcal-Aufnahme − (ΔGewicht × 7700 kcal/kg ÷ Tage).
   /// Fenster 21–28 Tage; null bei < 14 Tagen Daten oder Logging-Lücken > 40 %.
   TdeeEstimate? estimateTdee(List<({DateTime day, double kcal})> intake,
       List<BodyWeightLog> weights);
   /// Lineare Trend-Extrapolation auf targetWeightKg → erwartetes Datum.
   DateTime? projectedGoalDate(List<BodyWeightLog> weights, double targetKg);
   ```
   Gewichtsglättung: 7-Tage-EMA gegen Tagesschwankungen.
2. **Provider:** `tdeeProvider = FutureProvider<TdeeEstimate?>` im Health-Modul.
3. **UI:** Karte im Stats-Tab: „Dein Erhaltungsbedarf: ~2.340 kcal · Defizit-Ø:
   −310 kcal/Tag · Ziel 82 kg erreicht ≈ 14. Sep". Im Gewichts-Chart
   (fl_chart, vorhanden) Trendlinie als gestrichelte Serie ergänzen.
4. **Tests:** Estimator mit synthetischen Verläufen (konstant, linear, verrauscht,
   Lücken) — reine Dart-Logik, gut testbar.

#### F5 · Auto-Backup

**Datenbasis/Bausteine:** `BackupService.createBackup()` vorhanden.

1. **Settings (Muster settings_provider):** `autoBackupEnabled` (bool),
   `autoBackupIntervalDays` (1/7/30), `autoBackupDir` (String?),
   `autoBackupKeepCount` (int, Default 5), `lastAutoBackupAt` (DateTime?).
2. **`lib/services/auto_backup_service.dart` (neu):** `runIfDue()` — prüft
   Intervall gegen lastAutoBackupAt, erstellt Backup, löscht älteste über
   keepCount (Dateiname-Pattern `lifeos-backup-*.zip` im Zielordner), aktualisiert
   Timestamp. **Ausschlüsse:** `cache/` und `exports/` (siehe S8-Finding) —
   dafür `createBackup` um Parameter `excludeDirs` erweitern.
3. **Trigger:** Desktop: beim App-Start + alle 6 h via `Timer.periodic` in einem
   Side-Effect-Provider (Muster expiryNotificationScheduler). Android: beim
   App-Start (kein Background-Job nötig für v1).
4. **UI:** Settings-Sektion „Automatisches Backup" mit Ordnerwahl
   (file_picker `getDirectoryPath`), Status „Zuletzt: …".

#### F6 · Inventur-Modus

**Datenbasis:** `locations` (hierarchisch), `item_states.locationId`,
stocktake-Flow in `inventoryOpsProvider.stocktake()` — alles vorhanden.

1. **UI `lib/screens/inventory/stocktake_screen.dart` (neu):** Lagerort wählen →
   Liste aller Entries dort, je Zeile Ist-Menge groß, daneben Stepper/Feld;
   „Stimmt"-Haken übernimmt unverändert, Korrektur ruft `stocktake()` auf.
   Fortschritt „12/30 geprüft" oben; ungeprüfte zuerst.
2. **Route:** `/haushalt/stocktake` + Einstieg im Inventar-Menü und als
   Schnellaktion.
3. **Kein Schema nötig** — stocktake-Events existieren; „geprüft am" ergibt sich
   aus dem letzten stocktake-Event je Entry.

#### F7 · Wochen-Report Health

**Datenbasis:** dailyNutritionTotals, body_weight_logs, workouts, user_profile-Ziele.

1. **`lib/health/utils/weekly_report.dart` (neu):** `WeeklyReport.compute(...)` —
   Ø kcal, Protein-Zielquote (Tage ≥ proteinTargetG / 7), Gewichts-Delta
   (EMA Wochenanfang vs. -ende), Workout-Anzahl, Wasser-Ø.
2. **UI:** Karte oben im Stats-Tab („Deine Woche"), expandierbar.
3. **Push (optional, Stufe 2):** So 19:00 via NotificationService.zonedSchedule —
   Settings-Toggle `weeklyReportNotification`.

#### F8 · Lebensmittel-Budget

**Datenbasis:** `item_events type='purchase'` mit `price` — vorhanden (Preishistorie
nutzt sie schon).

1. **Settings:** `monthlyGroceryBudget` (double?, null = aus).
2. **DB:** `Future<double> purchaseSumForRange(DateTime from, DateTime to)` —
   SUM(price) über purchase-Events (Achtung: price ist Gesamtpreis des Kaufs,
   Semantik dokumentieren).
3. **UI:** Dashboard-Karte mit Fortschrittsbalken „427 € / 600 € · Monat zu 71 %
   vorbei" (Balken vs. Monatsfortschritt = sofort ablesbar ob über Plan);
   Tap → bestehende Jahresstatistik. Farbwechsel bei Budget-Überschreitung.

#### F9 · Garantie-Tracking

**Schema v43:** `items.warrantyMonths` (int nullable).

1. **Formular:** Feld „Garantie (Monate)" im Geräte-Abschnitt des item_form
   (nur für Nicht-Lebensmittel-Kategorien anzeigen).
2. **Ableitung:** Garantieende = ältestes purchase-Event + warrantyMonths
   (Fallback: item.createdAt). Helper in DB:
   `Future<DateTime?> warrantyEndForItem(String itemId)`.
3. **UI:** Zeile im Item-Detail („Garantie bis 12.03.2027 · noch 8 Monate",
   rot < 60 Tage); Dashboard-/Aufgaben-Anbindung: beim Unterschreiten von
   60 Tagen einmalig Task erzeugen („Garantie X läuft ab — Belege prüfen") —
   Wiederverwendung des Task-Systems statt neuem Notification-Kanal.
   Rechnung anhängen: entity_photos existiert bereits am Item-Detail.

#### F10 · Reste einlagern nach Kochen

**Datenbasis:** `prepared_dishes` (Tabelle + watchPreparedDishes vorhanden!).

1. **`_CookRecipeSheet` (nach U3-Fix):** Nach erfolgreichem Ausbuchen Dialog
   „Reste übrig?" → Portionsanzahl-Stepper → `insertPreparedDishe(...)` mit
   `name = recipe.title`, `portions`, `expiresAt = now + 3 Tage` (editierbar),
   `recipeId`-Verknüpfung.
2. **Kreis schließen:** Prepared Dishes erscheinen bereits im Expiry-Flow —
   beim Verzehr über das Tagebuch (`source='meal'`) prepared_dish als Quelle
   anbieten (Nährwerte aus dem Rezept ÷ Portionen).

#### F11 · Android App Shortcuts

1. **Package:** `quick_actions` (^1.1.x, offizielles Flutter-Plugin).
2. **`main.dart`/eigener Service:** Shortcuts registrieren: „Einkauf erfassen"
   (→ Kassenbon-Modus aus E1), „Scannen", „Tagebuch". Callback navigiert via
   Router; auf Desktop no-op.

#### F12 · Daten-Hygiene-Check

1. **`lib/services/data_health_service.dart` (neu):** drei Queries —
   EAN-Duplikate (GROUP BY ean HAVING COUNT>1), Events ohne Item (LEFT JOIN
   items IS NULL), recipe_ingredients mit itemId auf gelöschtes Item.
2. **UI:** Settings → „Daten prüfen": Befundliste mit Aktionen
   (Duplikat zusammenführen = Events/Entries auf Ziel-Item umhängen +
   Quell-Item trashen; Waisen löschen).

#### F13 · Desktop Drag & Drop

1. **Package:** `desktop_drop` (^0.4.x).
2. **Item-Detail:** `DropTarget` um die Foto-Sektion — abgelegte Bilddateien
   laufen durch denselben Pfad wie der image_picker-Import (inkl.
   MIME-Validierung aus Issue #10 — **Abhängigkeit**, erst #10 fixen).

**Empfohlene Reihenfolge innerhalb 6d:** F5 → F3 → F8 → F7 → F10 (alle klein,
sofortiger Nutzen) → F1 → F4 → F2 (Mittel, bauen auf Phase U auf) → F6 → F9 →
F11–F13. F2 setzt Phase U (convertQty) voraus, F13 setzt Issue #10 voraus.

---

## Teil 7 — Empfohlene Umsetzungs-Phasen

### Phase U — „Einheiten & Buchung reparieren" (VOR allem anderen)
> Nutzer-O-Ton: Falsche Ausbuchung + langsame Erfassung machen die App unbrauchbar.
> Das ist der Kern-Loop der App — vor Sync, vor allem anderen.

1. U5: Umrechnungs-Testmatrix schreiben (Ist-Bugs als Failing Tests)
2. U4: Packungs-Definition am Artikel (packageContentQty/Unit) + `resolveConversions()`
3. U1: Deduct-Sheet-Vorbelegung = konvertierte Tagebuchmenge
4. U2: `_computeServings` mit `unitToGrams` (Stück-Zutaten)
5. U3: Rezept-Kochen mit Konvertierung + Mismatch-Warnung
6. E1: Kassenbon-Modus (Batch-Scan-Loop)
7. E2: Direktbuchung mit Undo
8. E3: Einkaufsliste → Batch-Einbuchen

### Phase S — „Sync reparieren & absichern"
> Ohne diese Phase ist Phase-5-Sync ein Sicherheitsrisiko ohne Funktionsnutzen.

1. F4: `rebuildItemStates()` implementieren (+ Tests)
2. F1: `syncStatus`-Update nach Push
3. F2: Projektion-Rebuild nach Pull
4. F3: Stammdaten-Sync (items zuerst, dann Rest)
5. S2: PSK → SecretStorage
6. S5: insertOrIgnore statt Upsert
7. S1/S3/S4/S6: HMAC-Auth, Rate-Limit, constant-time, Body-Limit
8. 5.1/5.3: QR-Pairing + Auto-Sync (UX-Abschluss)

### Phase Q — „Qualität & Fundament"
1. T1: Test-Kandidaten 1–5 umsetzen (Ziel: Kernlogik >60 %)
2. A2: DAOs einführen, Monster-Screens splitten
3. A1: i18n-Entscheidung treffen und durchziehen
4. Offene GitHub-Issues #3–#8 abarbeiten
5. S7: Foto-Key vault-gebunden machen
6. Backup: cache/ + exports/ ausschließen

### Phase R — „Release-fähig"
1. T2: Release-Workflow mit Tags + GitHub Releases
2. A4: Keyboard-Shortcuts + MenuBar Desktop
3. 5.7: Fenster-Persistenz
4. A5: Dependency-Sprint (riverpod 3, go_router 17, …)
5. macOS Codesigning/Notarization klären

### Phase F — „Features"
1. Meal-Plan → Einkaufsliste
2. Abfall-Auswertung
3. Quick Wins aus Teil 6d: F5 Auto-Backup → F3 Mindestbestand lernen →
   F8 Budget → F7 Wochen-Report → F10 Reste einlagern
4. A3: Automation-Trigger-Engine
5. Datengetriebene Features: F1 Vorratsreichweite → F4 TDEE-Prognose →
   F2 „Was kann ich kochen?" (setzt Phase U voraus)
6. mDNS, CSV-Import, F6/F9/F11–F13, weitere P2/P3 nach Bedarf

> Detaillierte Integrationspläne zu allen F-Nummern: Teil 6d.

---

*Erstellt: 2026-06 · Deep-Dive über gesamte Codebase · Ergänzt Tiefenscan Mai 2026*
