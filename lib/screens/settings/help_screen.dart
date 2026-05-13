import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hilfe & Anleitung')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _Section(
            icon: Icons.home_outlined,
            title: 'Übersicht',
            body: 'LifeOS ist dein lokales Haushalts- und Lebens-Management-System. '
                'Alle Daten werden lokal auf deinem Gerät gespeichert (Vault-Ordner). '
                'Kein Cloud-Konto erforderlich – du hast immer die volle Kontrolle über deine Daten.',
          ),
          _Section(
            icon: Icons.folder_outlined,
            title: 'Vault',
            body: 'Ein Vault ist ein Ordner auf deinem Gerät, der die Datenbank und alle '
                'zugehörigen Dateien enthält.\n\n'
                '• Beim ersten Start wählst du einen Ordner als Vault.\n'
                '• Du kannst mehrere Vaults haben (z. B. einen pro Haushalt).\n'
                '• Backup = den Vault-Ordner kopieren oder über Einstellungen → Backup erstellen als ZIP exportieren.\n'
                '• Tipp: Für einen sauberen Wechsel zwischen Vaults verwende Einstellungen → Daten exportieren '
                '(JSON) statt einem Backup – so werden keine Vault-spezifischen Daten übertragen.',
          ),

          // ── Inventar ──────────────────────────────────────────────────────
          _Section(
            icon: Icons.inventory_2_outlined,
            title: 'Inventar – Artikel',
            body: 'Artikel sind alle Produkte in deinem Haushalt.\n\n'
                '• + Neuer Artikel: Tippe den + Button oder scanne einen Barcode.\n'
                '• Barcode scannen: Öffnet die Kamera, sucht den EAN-Code und lädt Produktdaten '
                'automatisch von Open Food Facts.\n'
                '• Bestandseinheit: Die Einheit, in der der Gesamtbestand summiert wird.\n'
                '• Standard-Lagerort & Lagerort (geöffnet): Werden beim Einlagern / Öffnen auto. vorausgewählt.\n'
                '• Tara-Gewicht: Verpackungsgewicht für Netto-Mengenberechnung bei Behältern.\n'
                '• Nährwerte: Per 100 g – werden im Portionsrechner skaliert.\n'
                '• Einheiten (artikelspezifisch): z. B. 1 Packung = 500 g.\n'
                '• Ratings: Sterne (1–5), Favorit (Herz), Abgelehnt (Daumen runter) direkt im Artikel-Detail.',
          ),
          _Section(
            icon: Icons.add_shopping_cart,
            title: 'Inventar – Einlagern',
            body: 'Tippe auf einen Artikel → "Einlagern"-Button (FAB unten).\n\n'
                '• Menge & Einheit, Lagerort, MHD, Preis & Geschäft, Notizen.\n'
                '• Zustand: frisch / tiefgefroren / aufgetaut (mit Datum).\n'
                '• Container: Behälter verknüpfen für Tara-Abzug.\n'
                '• Buchung bearbeiten: Im Artikel-Detail auf ✎ neben einer Einlagerung tippen.',
          ),
          _Section(
            icon: Icons.remove_circle_outline,
            title: 'Inventar – Verbrauchen & Verlauf',
            body: 'Tippe auf ⊖ neben einer Einlagerung → Menge + Grund eingeben.\n\n'
                '• Verlauf: Alle Ereignisse (Einkauf, Verbrauch, Umlagerung …) sind im Bereich '
                '"Verlauf" des Artikel-Details sichtbar.\n'
                '• Detail anzeigen: Auf einen Verlaufseintrag tippen zeigt alle Details '
                'inkl. geschätztem Warenwert.\n'
                '• Rückbuchen: Bei Verbrauchseinträgen erscheint der Button "Rückbuchen" – '
                'öffnet das Einlagern-Formular vorausgefüllt, um einen falschen Verbrauch rückgängig zu machen.',
          ),
          _Section(
            icon: Icons.filter_alt_outlined,
            title: 'Inventar – Filtern & Suchen',
            body: '• Suche: Suchleiste oben – X-Button löscht die Eingabe komplett.\n'
                '• Kategorie-Filter: Horizontal scrollbare Chips (Lebensmittel, Elektronik …).\n'
                '• Tag-Filter: Erscheint nach Kategorie-Auswahl.\n'
                '• Quick-Filter: Favoriten (♥), Sterne-Mindestbewertung (tippt durch 3★→4★→5★→aus), '
                'Abgelehnte Artikel.\n'
                '• Lagerwert: € Button in der AppBar zeigt Gesamtwert, Verteilung nach Kategorie und Lagerort.',
          ),
          _Section(
            icon: Icons.thermostat_outlined,
            title: 'Inventar – Zustände & Einfrieren',
            body: '• Jeder Bestandseintrag hat einen Zustand: frisch / tiefgefroren / aufgetaut.\n'
                '• Zustand ändern: Im Artikel-Detail → ↕ Button neben einer Einlagerung.\n'
                '• Eingefroren am / Aufgetaut am: Wird mit dem Zustand gespeichert.\n'
                '• Schneeflocken-Badge in der Inventarliste zeigt gefrorene / aufgetaute Einträge.',
          ),
          _Section(
            icon: Icons.category_outlined,
            title: 'Inventar – Produktgruppen & Mindestbestand',
            body: 'Produktgruppen bündeln ähnliche Artikel (z. B. "Milch" = Bio + Laktosefrei).\n\n'
                '• Mindestbestand: App zeigt in der Einkaufsliste alle Gruppen, '
                'deren Summe unter dem Minimum liegt.\n'
                '• Zugänglich über: AppBar → Gruppen-Icon oder Einkaufsliste → Einstellungen.',
          ),
          _Section(
            icon: Icons.label_outlined,
            title: 'Tags, Kategorien & Eigenschaften',
            body: '• Tags: Pro Kategorie definiert (Lebensmittel-Tags ≠ Elektronik-Tags).\n'
                '  Vergabe im Artikel-Formular, Filter in der Inventarliste.\n'
                '• Custom-Kategorien: Einstellungen → Kategorien → eigene Kategorien anlegen.\n'
                '• Produkttypen & Vorlagen: vordefinierte Feldsets (z. B. Elektronik = "Seriennummer, '
                'Garantie bis"). Im Artikel-Formular auswählbar.\n'
                '• Custom Properties: individuelle Felder pro Vorlage werden im Artikel-Detail angezeigt.',
          ),

          // ── Einkaufsliste ────────────────────────────────────────────────
          _Section(
            icon: Icons.shopping_cart_outlined,
            title: 'Einkaufsliste',
            body: 'Automatisch berechnet aus Produktgruppen mit Mindestbestand.\n\n'
                '• Auto-Bedarf: Alle Gruppen unter Mindestbestand erscheinen mit Fortschrittsbalken.\n'
                '• Manuelle Einträge: + Button → Name, Menge, Einheit, Geschäft, optional Artikel verknüpfen.\n'
                '• Verlinkter Eintrag: Ist ein manueller Eintrag mit einem Artikel verknüpft, '
                'wird er wie ein Auto-Bedarf dargestellt – mit Live-Bestand und "Einlagern"-Button.\n'
                '• Bearbeiten: PopupMenu (⋮) bei manuellen Einträgen → Bearbeiten / Löschen.\n'
                '• Kaufen aus Artikel-Detail: "Kaufen"-Button auf der Artikel-Seite fügt den Artikel '
                'direkt zur Einkaufsliste hinzu.',
          ),

          // ── Rezepte & Gerichte ────────────────────────────────────────────
          _Section(
            icon: Icons.menu_book_outlined,
            title: 'Rezepte',
            body: '• Rezept erstellen: + Button – Name, Zutaten, Schritte, Tags, Fotos.\n'
                '• Mealie-Import: Rezepte per URL importieren.\n'
                '• Raster-/Listenansicht: Toggle in der AppBar.\n'
                '• Ablaufende-Zutaten-Filter: Chip "Ablaufende Zutaten" zeigt Rezepte, '
                'die Artikel mit baldiger Ablaufzeit nutzen.\n'
                '• Geschätzte Kosten: Im Rezept-Detail am Ende der Zutaten-Liste – '
                'berechnet aus Ø-Kaufpreisen der verknüpften Zutaten.',
          ),
          _Section(
            icon: Icons.restaurant_menu_outlined,
            title: 'Gerichte (Mahlzeit-Vorlagen)',
            body: 'Gerichte sind Essens-Vorlagen (z. B. "Haferflocken mit Milch").\n\n'
                '• Fotos: via Popup-Menü (⋮) → Fotos hinzufügen.\n'
                '• Raster-/Listenansicht: Toggle in der AppBar.\n'
                '• Schnell-Verbuchen: Play-Button ▷ im Listen-Item öffnet den Verbrauch-Dialog direkt.\n'
                '• Mahlzeit-Planung: Gerichte und Rezepte per Drag & Drop in den Wochenplaner.',
          ),

          // ── Health ────────────────────────────────────────────────────────
          _Section(
            icon: Icons.monitor_weight_outlined,
            title: 'Gesundheit – Gewicht & Körper',
            body: '• Gewichtsverlauf: Werte (inkl. Fett%, Muskeln%, Viszeral, Wasser, Knochen) eintragen.\n'
                '• Liniendiagramm mit Aktuell / Min / Max / Durchschnitt.\n'
                '• Körpermaße: Brust, Taille, Hüfte, Arme, Oberschenkel etc.\n'
                '• Einträge können einzeln gelöscht werden.',
          ),
          _Section(
            icon: Icons.restaurant_outlined,
            title: 'Gesundheit – Ernährungstagebuch',
            body: '• Kalorienbudget und Makro-Ziele in den Einstellungen hinterlegen.\n'
                '• Tagesansicht: kcal-Fortschrittsbalken, Wasser-Tracker, Mahlzeiten-Slots.\n'
                '• Lebensmittel suchen: Lupe → OpenFoodFacts-Suche → Portion wählen → einbuchen.\n'
                '• Gerichte einbuchen: direkt aus dem Tagebuch → Portion anpassen.\n'
                '• Daumen-Bewertung: schnelle Qualitätsbewertung pro Mahlzeit.',
          ),
          _Section(
            icon: Icons.fitness_center_outlined,
            title: 'Gesundheit – Fitness',
            body: '• Übungen: 50+ vordefiniert, eigene hinzufügbar (Name, Kategorie, Typ).\n'
                '• Workouts: Übungen zusammenstellen, Sätze mit Gewicht / Wiederholungen / '
                'Dauer / Distanz erfassen.\n'
                '• Verlauf: alle Workouts chronologisch mit Gesamtvolumen.',
          ),
          _Section(
            icon: Icons.photo_camera_outlined,
            title: 'Gesundheit – Privater Foto-Bereich',
            body: '• AES-256-GCM-verschlüsselte Körperfotos (Vorher/Nachher).\n'
                '• App-Lock: Fotos erst nach Entsperren sichtbar.\n'
                '• Fotos werden nie in der normalen Galerie gespeichert.',
          ),

          // ── Aufgaben ──────────────────────────────────────────────────────
          _Section(
            icon: Icons.task_outlined,
            title: 'Aufgaben',
            body: '• Aufgaben mit Titel, Beschreibung, Priorität (Niedrig / Mittel / Hoch), '
                'Fälligkeitsdatum, Wiederholung.\n'
                '• Unteraufgaben: Im Aufgaben-Detail einklappbar dargestellt.\n'
                '• Artikel-Verlinkung: Aufgabe mit einem Inventar-Artikel verknüpfen.\n'
                '• Fotos: Im Aufgaben-Bearbeitungs-Dialog über den Foto-Bereich.\n'
                '• Sortiert nach Fälligkeitsdatum in Gruppen: Überfällig / Heute / Diese Woche / Später.',
          ),

          // ── Allgemein ────────────────────────────────────────────────────
          _Section(
            icon: Icons.straighten,
            title: 'Einheiten & Umrechnung',
            body: '• Eigene Einheiten erstellen oder vorhandene umbenennen.\n'
                '• Globale Umrechnungen: gelten für alle Artikel (z. B. 1 kg = 1000 g).\n'
                '• Artikel-spezifische Umrechnungen: z. B. 1 Packung = 14 Scheiben.\n'
                '• Amerikanische Einheiten (Cup, oz, lb …) sind vorausgefüllt.',
          ),
          _Section(
            icon: Icons.qr_code_scanner,
            title: 'Barcode-Scanner',
            body: '• Öffne den Scanner über den + FAB → Barcode scannen.\n'
                '• Bekannter EAN: öffnet den Artikel direkt.\n'
                '• Unbekannter EAN: öffnet das Erstellungsformular mit vorausgefülltem EAN '
                'und lädt Produktdaten von Open Food Facts.',
          ),
          _Section(
            icon: Icons.add_circle_outline,
            title: 'Schnellaktionen (FAB)',
            body: 'Der zentrale + Button in der Fussleiste öffnet die Schnellaktionen.\n\n'
                '• Einstellungen → Schnellaktionen: auswählen, welche Aktionen erscheinen sollen.\n'
                '• Verfügbar: Artikel einlagern, Ausbuchen, Aufgabe, Wunschliste, Rezept, Barcode.',
          ),
          _Section(
            icon: Icons.backup_outlined,
            title: 'Backup & Wiederherstellung',
            body: '• Einstellungen → Backup erstellen: exportiert den kompletten Vault als ZIP '
                '(inkl. Fotos und Datenbank).\n'
                '• Einstellungen → Backup wiederherstellen: ZIP auswählen und einspielen.\n'
                '• Hinweis: Backups sind vault-spezifisch. Beim Wiederherstellen in einen anderen '
                '(z. B. geschützten) Vault können Konflikte entstehen.\n'
                '• Manuelles Backup: den Vault-Ordner einfach kopieren.',
          ),
          _Section(
            icon: Icons.upload_outlined,
            title: 'Daten-Export & Import',
            body: '• Einstellungen → Daten exportieren: erstellt eine JSON-Datei mit allen '
                'Artikeln, Bestand, Rezepten, Aufgaben usw. – ohne Fotos und vault-spezifische Daten.\n'
                '• Einstellungen → Daten importieren: JSON-Datei auswählen, alle vorhandenen '
                'Datensätze werden ergänzt oder überschrieben (upsert).\n'
                '• Ideal für den Wechsel zwischen Vaults oder als leichtgewichtiges Backup der reinen Daten.',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Section({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleSmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(body, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
