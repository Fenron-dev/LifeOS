---
created-date: 2026-04-05 11:46:21
modified-date: 2026-04-05 12:30:00
---
# Projektkonzept: Local-First Household & Life Management System (LifeOS)

---

# 1. Ziel des Systems

Entwicklung einer **Local-First Anwendung** zur Verwaltung von:

- Lebensmitteln & Vorräten
- Rezepten & Ernährung
- Einkäufen & Preisen
- Haushaltsgegenständen & Geräten
- Aufgaben & Wartung
- Wunschlisten & Planung
- Beliebig erweiterbar durch benutzerdefinierte Kategorien

**Kernprinzipien:**

- 100 % lokal (keine Cloud-Abhängigkeit)
- Synchronisation nur im Heimnetz (Desktop als optionaler Server)
- Modularer Aufbau (Features aktivier-/deaktivierbar)
- Event-basierte Datenhaltung (historisch & nachvollziehbar)
- **Portabel**: Ein Ordner = eine Instanz. Kopieren = vollständiges Backup.

---

# 2. Vault-System (Workspace-Konzept)

Ein **Vault** ist ein Ordner auf dem Gerät:

```
~/lifeos-haushalt/
├── lifeos.db          ← SQLite-Datenbank (alles drin)
├── photos/            ← Fotos (UUID.jpg, relativ referenziert)
├── exports/           ← JSON-Exporte, PDFs
└── cache/             ← Thumbnails, wegwerfbar (kein Backup nötig)
```

- Beim App-Start: Vault-Auswahl (zuletzt geöffnete Vaults + "Neuer Vault")
- **Backup = Ordner kopieren** — keine spezielle Backup-Funktion nötig
- Mehrere Vaults möglich: Haushalt, Ferienwohnung, Eltern
- Vaults können untereinander **verlinkt** werden (Cross-Vault-Referenzen, Phase 4+)
- Desktop-Vault kann als **Sync-Server** für Mobile dienen

---

# 3. Systemarchitektur

## Frontend

- Framework: **Flutter** (Dart)
- Plattformen: Mobile (Android/iOS) + Desktop (Windows/Linux/macOS)
- Primäre Nutzung Mobile: Barcode-Scan, schnelle Eingabe, Verbrauch
- Sekundäre Nutzung Desktop: Übersicht, Bulk-Verwaltung, Server-Rolle

## Adaptive UI-Breakpoints

| Breite | Layout |
|--------|--------|
| < 600px | Mobile: Bottom Navigation, 1 Panel |
| 600–1200px | Tablet: Side Rail + Content, Split-View für Rezepte |
| ≥ 1200px | Desktop: 3-Panel (Sidebar + Main + Detail), MenuBar |

## Backend (optional, lokal im Netzwerk)

- **Desktop-App** startet optional einen HTTP-Server (Dart `shelf`)
- Mobile-App synct Events über WiFi mit Desktop
- Kein externer Server, keine Cloud

## Datenbank

- Lokal: SQLite via **Drift ORM** (pro Vault eine DB-Datei)
- Migrationen: inkrementell versioniert

## Synchronisation

- Schema: Jedes Event hat `device_id` + `synced_at`
- Protokoll: HTTP REST, Pull (Events seit Timestamp) + Push (neue Events)
- Konfliktlösung: "Last event wins" pro Item (zunächst), später: Event-Reihenfolge
- Sync-Status: `pending | synced | conflict`

## Sprache / i18n

- Flutter ARB-Dateien: `l10n/app_de.arb` (Primary), `l10n/app_en.arb`
- Alle UI-Strings über `AppLocalizations.of(context)`

---

# 4. Grundlegende Architektur (Core-System)

Das gesamte System basiert auf 5 zentralen Konzepten:

## 4.1 Items

Repräsentieren alle Objekte im System:

- Lebensmittel (mit Barcode/EAN)
- Geräte & Inventar
- Wunschlisten-Einträge
- Custom-Kategorie-Einträge

**Erweiterte Item-Eigenschaften:**
- `productType`: `readyToEat` (TK, Konserve, Fertiggericht) | `needsCooking` (Rohzutat) | `ingredient` (Gewürz, Zutat ohne Einzelverzehr)
- `alwaysConsumedFully`: bool — beim Scan automatisch komplett verbraucht
- `openedFlag`: "Gilt als vorhanden wenn angebrochen?" (z.B. Ketchup = ja, Cracker-Packung = nein)
- `containerItemId`: FK → Item (Standard-Vorratsdose für dieses Produkt)
- `photos`: Liste von Fotos (UUID-Referenzen)
- `notes`: Freitextnotiz
- Fotos auch für Lagerorte und Geräte

---

## 4.2 Gruppen

Logische Zusammenfassungen:

- Produktgruppen (z.B. „Eier", „Haferflocken")
- Kategorien

Zweck:
- Mindestbestände definieren
- Vereinheitlichung verschiedener Marken/Produkte

---

## 4.3 Orte (Locations)

Hierarchisches Lagersystem mit Fotos:

```
Küche
├── Kühlschrank (Foto möglich)
│   └── Oberstes Fach
└── Schrank
Keller
└── Regal A > Box 3
```

---

## 4.4 Events (zentrales Konzept)

Alle Änderungen werden als unveränderliche Events gespeichert:

- Kauf (Produkt, Menge, Preis, Geschäft)
- Verbrauch (Einzel, via Standard-Mahlzeit, via Rezept)
- Inventur (Korrektur Direktbestand / Differenz)
- Umlagerung
- Zustandswechsel (frisch → eingefroren → aufgetaut)
- Öffnen (verknüpft automatisch mit Container/Tara)

**Aktueller Zustand wird aus Events berechnet** (+ materialisierte Projektion `item_states` für Performance).

Event-Schema:
```
id, type, item_id, quantity, unit, location_id,
price, store, device_id, created_at, synced_at, sync_status
```

---

## 4.5 Regeln & Automation

### Statische Regeln:
- Mindestbestand-Alerts
- Ablaufdatum-Warnungen
- Wiederkehrende Aufgaben

### Dynamisches If→Then-System:
Visueller Regel-Builder:
- **Trigger**: Manuell | Zeit (z.B. täglich 8:00) | Event (Produkt läuft ab) | Schwellwert (Bestand < Min)
- **Bedingungen (Filter)**: Tag = X AND Kategorie = Y AND Wert > Z (kombinierbar)
- **Aktionen**: Benachrichtigung | Aufgabe erstellen | Einkaufsliste erweitern | Webhook
- Regeln sind ein-/ausschaltbar und manuell auslösbar

---

# 5. Tag-System

## Kategoriespezifische Tags

Tags sind **pro Kategorie** definiert — keine Vermischung:
- Lebensmittel-Tags: Vegan, Zuckerfrei, Bio, Glutenfrei
- IT/Elektronik-Tags: Desktop, Server, Mobil, Defekt

## Tag-Hierarchie (Subtags)

```
Küche
└── Mediterran
    └── Leicht
Geschenk
└── Persönlich
    └── Frau
```

- Sortierung und Filterung über Tag-Baum möglich
- Tags haben Farbe + Icon

---

# 6. Lebensmittel & Produktverwaltung

## 6.1 Produkt (Barcode-basiert)

- EAN-Code (Barcode-Scanner)
- Name, Marke, Hersteller
- Nährwerte (manuell oder aus OpenFoodFacts)
- `productType` (readyToEat / needsCooking / ingredient)
- `alwaysConsumedFully`
- `openedFlag`
- Standard-Container (`containerItemId`) für Tara-Automatik
- Fotos, Notizen

**OpenFoodFacts-Integration:**
- On-Demand via EAN
- Nutzer wählt welche Felder übernommen werden
- Lokal cachebar in DB

---

## 6.2 Smart Tara / Container-System

- Behälter-Items haben ein **Tara-Gewicht** (z.B. Vorratsdose 12 = 180g)
- Beim Öffnen eines Produkts → automatisch Standard-Container verknüpfen
  - "Pizzamehl → Vorratsdose 12 (Tara: 180g)"
- Beim Wiegen: Tara automatisch abziehen
- Händisch überschreibbar (anderer Behälter wählbar)
- Event "Umfüllen in Behälter X" wird gespeichert

---

## 6.3 Inventar

- Produkt oder Produktgruppe
- Menge + Einheit
- Lagerort
- Zustand: frisch | eingefroren | aufgetaut
- Ablaufdatum (MHD / "Verbrauchen bis" / automatisch berechnet z.B. +3 Tage nach Öffnen)
- Eingefroren am / Aufgetaut am

---

# 7. Einheiten & Umrechnung

## Ebenen:
1. Global (z.B. 1 kg = 1000 g)
2. Produktgruppe
3. Produktspezifisch (Override)

## Kauf vs. Nutzung
- Kauf-Einheit (z.B. Packung à 500g)
- Nutz-Einheit (z.B. Gramm)

## Tara
- Verpackungsgewicht wird hinterlegt → tatsächlicher Inhalt automatisch berechnet

---

# 8. Einkauf & Preise

## Kauf-Event enthält:
- Produkt
- Menge + Einheit
- Preis
- Geschäft

## Berechnungen:
- Preis pro Einheit
- Durchschnittspreis (über Zeit)
- Rezeptkosten

## Einkaufslisten-Modul:
- Automatisch generiert aus Mindestbestand-Unterschreitungen
- Manuell ergänzbar
- Mehrere Listen (Wocheneinkauf, Baumarkt, etc.)
- Export / Teilen

---

# 9. Bestand & Inventur

## Inventur-Modi:
1. Direktkorrektur (absoluter Wert)
2. Differenzbasierte Inventur (Delta)

---

# 10. Verbrauch & Ernährung

## Verbrauchserfassung

- Per Barcode-Scan (alwaysConsumedFully berücksichtigen)
- Mit Mengenvorschlägen (letzter Verbrauch, Durchschnitt)
- Via **Standard-Mahlzeiten** (Consumption Templates):
  - "Frühstück = 2 Scheiben Schwarzbrot + 20g Butter + 4 Scheiben Salami"
  - Bei Scan: welche Variante (wenn mehrere vorhanden)?
  - Alle Zutaten werden automatisch reduziert

## Ernährungstracking
- Kalorien, Makronährstoffe
- Tagesübersicht (wie lokales MyFitnessPal)
- Kombination aus Einzelprodukten + Standard-Mahlzeiten

## Nutzerprofil
- Gewicht, Zielwerte (Kalorien etc.)
- Gewichtsverlauf über Zeit

---

# 11. Rezepte

## Funktionen:
- Manuelle Erstellung (Zutaten, Schritte, Nährwerte, Zubereitungszeit)
- Import aus Mealie (JSON)
- Video-Link zum Rezept (YouTube-URL oder lokale Datei)

## Zutaten:
- Verknüpfung mit Produkten/Gruppen
- Nährwertberechnung: Summe aller Zutaten

## Tablet Split-View:
- Rechts: Video (eingebettet oder verlinkt)
- Links: Zutaten + Zubereitungsschritte (einzeln abhakbar)

## Verbrauch:
- Zutaten automatisch gemappt oder per Scan
- Standard-Mahlzeit aus Rezept erstellen

## Kombinationsvorschläge:
- Welche Gerichte passen gut zusammen?
- Phase 1: Manuelle "passt-zu"-Tags
- Phase 2: Algorithmus via gemeinsame Tags + Verfügbarkeit

## Rezept als Wunsch:
- Gerichte können als Wunschlisten-Eintrag gespeichert werden
- "Ich möchte dieses Gericht mal kochen"

---

# 12. Haltbarkeit & Zustände

## Modi:
- MHD
- "Verbrauchen bis"
- Automatisch berechnet (z.B. +3 Tage nach Öffnen)

## Erweiterung:
- Eingefroren am / Aufgetaut am
- Zustandswechsel als Event gespeichert (Audit-Trail)

---

# 13. Geräte & Inventar

## Geräte:
- Kaufdatum, Garantie bis
- Dokumente (Rechnung, Anleitung)
- Zubehör (Verlinkung zu anderen Items)
- Fotos
- Notizen

## Nutzung:
- Tracking der letzten Verwendung (als Event)

## Inventar:
- Lagerort + Boxensystem
- Nutzungshäufigkeit

---

# 14. Aufgaben & Planung

## Features:
- Aufgaben erstellen (mit Notizfeld, Fotos)
- Wiederkehrende Aufgaben

## Wiederholungen:
- Stündlich, täglich, wöchentlich, monatlich, jährlich
- Komplexe Regeln (z.B. "jeden ersten Montag im Monat")

---

# 15. Wunschliste

- Titel, URL, Preis, Priorität
- Notizen
- Tags (kategoriespezifisch)
- Personenbezug (für wen?)
- **Verlinkung zu Rezepten** ("Ich wünsche mir dieses Gericht")
- **Verlinkung zu Items** ("Ich möchte dieses Gerät")
- Fotos

---

# 16. Benutzerdefinierte Kategorien (Phase 4)

Nutzer kann eigene Kategorien erstellen mit eigenen Feldern:

**Beispiel: "Bücher"**
- Felder: Autor (Text), ISBN (Text), Status (Enum: Ungelesen/Lese gerade/Gelesen), Bewertung (Zahl)

**Beispiel: "Elektronik"**
- Felder: Seriennummer (Text), Garantie bis (Datum), Modell (Text)

**Property-Typen:**
- Text, Zahl, Datum, Boolean, Enum (Auswahl), Item-Link (Referenz auf anderes Item)

**Tags** sind pro Kategorie definiert → keine Verwirrung über Kategorien hinweg

---

# 17. UI/UX Konzept

## Modularer Aufbau:
- Feature-basierte Navigation
- Features aktivieren/deaktivieren

## Notizfelder:
- Für jede Entität (Produkt, Kategorie, Rezept, Aufgabe, etc.)

## Fotos:
- Für Produkte, Items, Lagerorte, Geräte, Aufgaben
- Kamera + Galerie
- Thumbnail-Generierung im Hintergrund

---

# 18. Synchronisation

## Prinzip:
- Local First — App funktioniert immer ohne Netz
- Sync nur im Heimnetz

## Technik:
- Desktop-App startet optional HTTP-Server (Dart `shelf`)
- Mobile-App findet Desktop via mDNS oder manuelle IP-Eingabe
- Event-basierter Sync: Pull (Events seit Timestamp) + Push (neue Events)

## Konfliktlösung:
- Zunächst: "Last event wins" per Item (Timestamp)
- Später: Event-Reihenfolge (kausal)

---

# 19. Backup & Import

## Backup:
- Vault-Ordner kopieren = vollständiges Backup (Primärweg)
- Zusätzlich: JSON-Export (ohne Fotos oder mit)
- Vollständige DB-Sicherung

## Import:
- Mealie (Rezepte)
- OpenFoodFacts (Produkte via EAN)
- Eigenes Format

## OCR für Kassenbon (ambitioniert, Phase 4+):
- Foto von Kassenbon → automatisch Produkte + Preise erfassen
- `google_mlkit_text_recognition` (on-device, kein Cloud-OCR)

---

# 20. MVP-Phasen

## Phase 0 — Fundament
- Flutter-Projekt, Vault-System, Drift-Schema
- Adaptive Shell (Mobile + Desktop)
- i18n (Deutsch + Englisch)
- Foto-Handling, Basis-Navigation

## Phase 1 — Lebensmittel MVP
- Produkt-CRUD + Barcode-Scanner
- OpenFoodFacts-Integration
- Inventar (Menge, Einheit, Ort, Zustand)
- Ablaufdatum + Benachrichtigungen
- Event-Log (Kauf, Verbrauch, Inventur)
- JSON-Export / Vault-Backup

## Phase 2 — Bestand & Struktur
- Produktgruppen + Mindestbestand-Regeln
- Standard-Mahlzeiten (Consumption Templates)
- Smart Tara / Container-System
- Lagerort-Hierarchie mit Fotos
- Tag-System (kategoriespezifisch + Hierarchie)
- Einkaufslisten-Modul

## Phase 3 — Rezepte & Ernährung
- Rezept-CRUD + Mealie-Import
- Nährwertberechnung + Tagesübersicht
- Tablet Split-View (Video + Schritte)
- Kombinationsvorschläge (Tag-basiert)
- Wunschliste mit Rezept-Verlinkung

## Phase 4 — Erweitert
- Benutzerdefinierte Kategorien (Meta-Modell)
- Automation / If→Then-System
- Vault-Cross-Links
- OCR Kassenbon (experimentell)

## Phase 5 — Sync
- Desktop als lokaler Sync-Server (`shelf`)
- Event-Sync mit Android-App
- Konfliktlösung

---

# 21. Technische Leitentscheidungen

- Flutter + Dart (Single Codebase, alle Plattformen)
- SQLite via Drift ORM (Typ-Sicherheit, Migrationen)
- Riverpod 2 (State Management)
- go_router (Navigation)
- Vault = Ordner (Portabilität von Anfang an)
- Event-Sourcing + materialisierte Projektion (Performance)
- `shelf` Package für optionalen Desktop-HTTP-Server
- i18n mit Flutter ARB-Dateien (Deutsch primary)

---

# 22. Architekturprinzipien

- Event-driven statt zustandsbasiert
- Modular & erweiterbar (Custom Categories)
- Offline-First
- Nutzerkontrolle über Daten (kein Cloud-Zwang)
- Portabel (Vault = Ordner)
- Hohe Automatisierung durch Datenaggregation

---

# Ergebnis

Ein vollständig lokales, modulares, portables System zur Verwaltung und Optimierung von:

- Haushalt & Inventar
- Ernährung & Rezepten
- Planung & Aufgaben
- Wünsche & Einkäufe
- Beliebig erweiterbar (Custom Categories)

Mit Fokus auf: Automatisierung — Datenkontrolle — Erweiterbarkeit — Portabilität
