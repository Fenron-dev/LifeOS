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

## Teil 7 — Empfohlene Umsetzungs-Phasen

### Phase S — „Sync reparieren & absichern" (höchste Priorität)
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
3. A3: Automation-Trigger-Engine
4. mDNS, CSV-Import, weitere P2/P3 nach Bedarf

---

*Erstellt: 2026-06 · Deep-Dive über gesamte Codebase · Ergänzt Tiefenscan Mai 2026*
