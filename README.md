# LifeOS

**Local-First Household & Life Management System**

A Flutter application for managing groceries, inventory, recipes, appliances, fitness, tasks, and wish lists — across Android and Linux/Windows desktops with optional WiFi sync.

---

## ✅ Implemented Features

### Inventar & Haushalt
- **Inventar-Verwaltung** — Artikel mit Menge, Einheit, MHD und Lagerort verwalten
- **Barcode-Scan** — EAN-Lookup via OpenFoodFacts, sofortige Produkterkennung
- **Event-Sourcing** — Unveränderliches Event-Log (Einkauf, Verbrauch, Inventur, Umlagerung) mit materialisiertem Zustand
- **Verlaufs-Detail & Rückbuchen** — Jedes Ereignis anklickbar: Details mit Warenwert-Schätzung; Verbrauch per "Rückbuchen" rückgängig machen
- **Zustände** — frisch / tiefgefroren / aufgetaut mit Datum, inkl. Badge in Inventarliste
- **Container & Tara** — Behälter-Verlinkung und Tara-Gewicht für Netto-Mengenberechnung
- **Smart-Öffnen** — Auto-Umlagerung beim Öffnen zu konfiguriertem "Geöffnet-Lagerort"
- **Preise** — Kaufpreis je Bestandseintrag, Durchschnittspreis-Badge im Artikeldetail
- **Lagerort-Hierarchie** — verschachtelte Lagerorte (Kühlschrank → Oberes Fach)
- **Item-Gruppen & Mindestbestand** — Bestandsregeln pro Gruppe, automatische Einkaufsliste
- **Tags & Kategorien** — kategoriescoped Tags, Custom-Kategorien mit eigenen Feldern
- **Relationen** — Artikel-Verknüpfungen (Ersatz, Ergänzung, Behälter)
- **Custom Properties & Produkttypen** — flexible Felder je Vorlage / Produkttyp
- **Ratings** — Sterne (1–5), Favorit (Herz), Daumen runter; Filter im Inventar

### Inventar-Filter & -Übersicht
- **Filter** — Kategorie, Tags, Favoriten, Sterne-Mindestbewertung, Abgelehnte Artikel
- **Lagerwert-Übersicht** — Gesamtwert, Verteilung nach Kategorie und Lagerort (€-Schätzung)

### Einkaufsliste
- **Auto-Bedarf** — Artikel unter Mindestbestand erscheinen automatisch
- **Manuelle Einträge** — freie Positionen hinzufügen, bearbeiten, abhaken
- **Artikel verlinken** — manuelle Einträge mit Inventar-Artikel verknüpfen → Live-Bestand, Fortschrittsbalken, Einlagern-Flow
- **Geschäfte** — Einträge nach Geschäft gruppieren
- **Artikel aus Detailansicht** — "Kaufen"-Button auf Artikel-Seite fügt zur Einkaufsliste hinzu

### Rezepte
- **Rezeptverwaltung** — Zutaten, Schritte, Tags, Fotos
- **Mealie-Import** — Rezepte per URL aus Mealie importieren
- **Raster- und Listenansicht**
- **Ablaufende-Zutaten-Filter** — Rezepte anzeigen, die Artikel mit baldiger Ablaufzeit nutzen
- **Geschätzte Kosten** — Rezeptkosten basierend auf letzten Kaufpreisen der Zutaten
- **Mahlzeiten (Gerichte)** — Schnelle Verbrauchsvorlagen; Fotos via Popup; Raster- und Listenansicht
- **Mahlzeitenplanung** — Wochenplaner mit Drag-and-Drop

### Health-Tracking
- **Gewicht & Körperzusammensetzung** — Gewicht, Fett%, Muskel%, Viszeral, Wasser, Knochen
- **Ernährungstagebuch** — kcal, Makros (Protein, Fett, Kohlenhydrate) + Wasser
- **Lebensmittelsuche** — OpenFoodFacts-Integration mit Portionsanpassung
- **Fitness** — Übungen (50+ vorinstalliert), Workouts, Sätze mit Gewicht/Wdh./Dauer/Distanz
- **Privater Foto-Bereich** — AES-256-GCM-verschlüsselte Vorher/Nachher-Fotos

### Aufgaben & Wunschliste
- **Aufgaben** — Priorität, Fälligkeitsdatum, Wiederholung, Unteraufgaben, Artikel-Verlinkung
- **Wunschliste** — Wünsche mit Priorität und Preis
- **Artikel-Verlinkung** — Aufgaben mit Inventar-Artikeln verknüpfen

### Allgemein
- **Foto-System** — Fotos für Artikel, Rezepte, Aufgaben, Lagerorte (AES-verschlüsselt für Fotos)
- **Thumbnail-Cache** — automatische Thumbnail-Generierung für schnelle Ladelisten
- **Adaptives UI** — BottomNav (Mobil) / NavigationRail (Tablet) / 3-Panel-Sidebar (Desktop)
- **Dark/Light Mode** — systemabhängig
- **Vault-System** — gesamter App-Zustand in einem Ordner; Backup = Ordner kopieren

---

## ⏳ Noch offen / geplant

| Bereich | Feature |
|---|---|
| Inventar | i18n-konforme Strings (aktuell hardcoded DE) |
| Sync | WiFi-Sync Desktop↔Android (Phase 5) |
| Sync | PSK-basiertes Pairing (Sicherheit) |
| Automatisierung | If→Then Regeln (Automation-Regelwerk) |
| Backup | Export als ZIP inkl. Fotos |
| Benachrichtigungen | Ablauf-Alerts (flutter_local_notifications) |
| Desktop | MenuBar-Shortcuts für Linux/Windows/macOS |
| Wunschliste | Preisvergleich / Web-Link |
| Analyse | Verbrauchsstatistiken über Zeit |

---

## Tech Stack

| Layer | Technologie |
|---|---|
| UI | Flutter + Material 3 |
| State | Riverpod 2 (code-gen) |
| Datenbank | Drift ORM (SQLite, WAL mode, Schema v34) |
| Navigation | go_router |
| Sync-Server | shelf (optional, Desktop) |
| Barcode | mobile_scanner |
| Verschlüsselung | AES-256-GCM (pointycastle) |
| Fotos | image_picker + thumbnail isolate |

---

## Getting Started

```bash
# 1. Abhängigkeiten installieren
flutter pub get

# 2. Drift-Code generieren (nach Schema-Änderungen)
dart run build_runner build --delete-conflicting-outputs

# 3. Starten
flutter run -d linux          # Desktop (Linux)
flutter run                   # Android / Auto-Erkennung

# 4. Smoke-Tests
flutter test test/db/database_smoke_test.dart
```

## Build

```bash
flutter build apk --release   # Android APK
flutter build linux --release # Linux Bundle
```

---

## Architektur

### Vault-System

Der gesamte App-Zustand liegt in einem Ordner auf dem Gerät:

```
~/lifeos-haushalt/
├── lifeos.db     ← alle Daten (Drift/SQLite)
├── photos/       ← UUID-benannte Bilddateien
├── exports/      ← JSON-Exporte, PDFs
└── cache/        ← Thumbnails (löschbar, kein Backup nötig)
```

Backup = Ordner kopieren. Kein separates Exportfeature nötig.

### Event-Sourcing

Alle Bestandsänderungen sind **Events** (append-only, unveränderlich):

```
item_events  →  (Projektion)  →  item_states
(Wahrheitsquelle)                (schnelle Lesecaches)
```

### Datenfluss

```
Drift Tables → AppDatabase-Methoden → Riverpod Providers → UI Widgets
```

---

## Entwicklungsphasen

| Phase | Status | Scope |
|---|---|---|
| 0 | ✅ Done | Vault, Schema, Adaptive Shell |
| 1 | ✅ Done | Produkte, Barcode, EAN-Lookup, Inventar CRUD |
| 2 | ✅ Done | Event-Log, Stock-Operationen, Lagerorte |
| 3 | ✅ Done | Rezepte, Nutrition, Gruppen, Mahlzeiten |
| 4 | ✅ Done | Custom-Kategorien, Relationen, Vorlagen |
| 5 | ✅ Done | Automation-Regeln (Schema), Aufgaben |
| 6 | ✅ Done | Health-Tracking (Gewicht, Ernährung, Fitness, Fotos) |
| 6.9+ | ✅ Done | Ratings, Raster-Ansichten, Verlaufs-Details, Lagerwert |
| 7 | ⏳ Planned | WiFi-Sync Desktop↔Android (shelf-Server + PSK) |
| 8 | ⏳ Planned | Statistiken, Verbrauchsanalyse, Benachrichtigungen |

---

## License

MIT
