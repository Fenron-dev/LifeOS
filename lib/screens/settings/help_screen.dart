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
            body: 'LifeOS ist dein lokales Haushalts-Management-System. '
                'Alle Daten werden lokal auf deinem Gerät gespeichert (Vault-Ordner). '
                'Kein Cloud-Konto erforderlich. Du hast immer die volle Kontrolle über deine Daten.',
          ),
          _Section(
            icon: Icons.folder_outlined,
            title: 'Vault',
            body: 'Ein Vault ist ein Ordner auf deinem Gerät, der die Datenbank und alle '
                'zugehörigen Dateien enthält.\n\n'
                '• Beim ersten Start wählst du einen Ordner als Vault.\n'
                '• Du kannst mehrere Vaults haben (z. B. einen pro Haushalt).\n'
                '• Backup = den Vault-Ordner kopieren oder über Einstellungen → Backup erstellen als ZIP exportieren.',
          ),
          _Section(
            icon: Icons.inventory_2_outlined,
            title: 'Inventar – Artikel',
            body: 'Artikel sind alle Produkte in deinem Haushalt.\n\n'
                '• + Neuer Artikel: Tippe den + Button in der Fusszeile oder scanne einen Barcode.\n'
                '• Barcode scannen: Öffnet die Kamera, sucht den EAN-Code und lädt Produktdaten '
                'automatisch von Open Food Facts.\n'
                '• Bestandseinheit: Die Einheit, in der der Gesamtbestand summiert wird (z. B. g, Stück).\n'
                '• Standard-Lagerort: Wird beim Einlagern automatisch vorausgewählt.\n'
                '• Nährwerte: Per 100 g – werden im Portionsrechner skaliert.\n'
                '• Einheiten (artikelspezifisch): z. B. 1 Packung = 500 g – ermöglicht Einbuchen in Packungen.',
          ),
          _Section(
            icon: Icons.add_shopping_cart,
            title: 'Inventar – Einlagern',
            body: 'Tipp auf einen Artikel → "Einlagern"-Button.\n\n'
                '• Menge & Einheit: Wähle Menge und Einheit (auch artikelspezifische Einheiten).\n'
                '• Lagerort: Kühlschrank, Regal, Keller etc.\n'
                '• MHD: Mindesthaltbarkeitsdatum – die App warnt vor Ablauf.\n'
                '• Preis & Geschäft: Optional für Ausgaben-Tracking.\n'
                '• Buchung bearbeiten: Im Artikel-Detail auf ✎ neben einer Einlagerung tippen.',
          ),
          _Section(
            icon: Icons.remove_circle_outline,
            title: 'Inventar – Verbrauchen',
            body: 'Tipp auf ⊖ neben einer Einlagerung.\n\n'
                '• Menge eingeben und optional Einheit wählen – die App rechnet '
                'automatisch in die Lager-Einheit um.\n'
                '• "Alles verbraucht" entfernt die Einlagerung vollständig.',
          ),
          _Section(
            icon: Icons.category_outlined,
            title: 'Inventar – Produktgruppen',
            body: 'Produktgruppen bündeln ähnliche Artikel (z. B. "Milch" = Bio-Milch + Laktosefrei).\n\n'
                '• Mindestbestand: Die App zeigt in der Einkaufsliste alle Gruppen, '
                'deren Summe unter dem Minimum liegt.\n'
                '• Zugänglich über: AppBar → Gruppen-Icon oder Einkaufsliste.',
          ),
          _Section(
            icon: Icons.shopping_cart_outlined,
            title: 'Einkaufsliste',
            body: 'Automatisch berechnet aus Produktgruppen mit Mindestbestand.\n\n'
                '• Zeigt alle Gruppen, die unter dem definierten Mindestbestand liegen.\n'
                '• Tippe "Einkaufen" → wähle den Artikel → Einlagern-Formular öffnet sich direkt.',
          ),
          _Section(
            icon: Icons.menu_book_outlined,
            title: 'Rezepte',
            body: '• Rezept erstellen: + Button, Name, Zutaten, Schritte eingeben.\n'
                '• Mealie-Import: Rezepte aus einer Mealie-Instanz importieren (URL eingeben).\n'
                '• Zutaten verknüpfen: Zutat mit einem Artikel oder einer Gruppe verknüpfen '
                '– ermöglicht spätere Nährwert-Berechnung.',
          ),
          _Section(
            icon: Icons.restaurant_menu_outlined,
            title: 'Gerichte',
            body: 'Gerichte sind Essens-Vorlagen (z. B. "Haferflocken mit Milch").\n\n'
                '• Zutaten können mit echten Artikeln verknüpft werden.\n'
                '• Verknüpfte Zutaten mit Nährwerten zeigen eine Nährwert-Zusammenfassung '
                'im Gericht-Card.\n'
                '• Gerichte können unter Einstellungen → Mahlzeiten einer Mahlzeit '
                '(Frühstück, Mittagessen …) zugeordnet werden.',
          ),
          _Section(
            icon: Icons.restaurant_outlined,
            title: 'Mahlzeiten (Einstellungen)',
            body: 'Definiere deine täglichen Mahlzeiten-Slots:\n\n'
                '• Standard: Frühstück, Mittagessen, Abendessen, Snack, Süßigkeit, Getränk.\n'
                '• Eigene Mahlzeiten erstellen, umbenennen, löschen.\n'
                '• Per Drag & Drop die Reihenfolge ändern.\n'
                '• Gerichte und Rezepte einer Mahlzeit zuweisen – '
                'Grundlage für das spätere Ernährungstagebuch.',
          ),
          _Section(
            icon: Icons.task_outlined,
            title: 'Aufgaben',
            body: '• Aufgaben mit Titel, Fälligkeitsdatum und Notiz erstellen.\n'
                '• Status: Offen → Erledigt.\n'
                '• Sortiert nach Status und Fälligkeitsdatum.',
          ),
          _Section(
            icon: Icons.bar_chart_outlined,
            title: 'Statistik',
            body: '• Gewichtsverlauf: Werte eintragen und als Liniendiagramm verfolgen.\n'
                '• Zeigt Aktuell / Min / Max / Durchschnitt.\n'
                '• Einträge können einzeln gelöscht werden.',
          ),
          _Section(
            icon: Icons.straighten,
            title: 'Einheiten & Umrechnung',
            body: '• Einheiten: Eigene Einheiten erstellen oder vorhandene umbenennen.\n'
                '• Globale Umrechnungen: gelten für alle Artikel (z. B. 1 kg = 1000 g).\n'
                '• Artikel-spezifische Umrechnungen: z. B. 1 Packung = 14 Scheiben – '
                'nur für diesen Artikel.\n'
                '• Amerikanische Einheiten (Cup, oz, lb, fl oz …) sind bereits vorausgefüllt.',
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
            icon: Icons.backup_outlined,
            title: 'Backup & Wiederherstellung',
            body: '• Einstellungen → Backup erstellen: exportiert den Vault als ZIP.\n'
                '• Einstellungen → Backup wiederherstellen: ZIP auswählen und einspielen.\n'
                '• Manuelles Backup: den Vault-Ordner (Standard: lifeos-haushalt) kopieren.',
          ),
          _Section(
            icon: Icons.add_circle_outline,
            title: 'Schnellaktionen (FAB)',
            body: 'Der zentrale + Button in der Fussleiste öffnet die Schnellaktionen.\n\n'
                '• Einstellungen → Schnellaktionen: auswählen, welche Aktionen erscheinen sollen.\n'
                '• Verfügbar: Artikel einlagern, Ausbuchen, Aufgabe, Wunschliste, Rezept, Barcode.',
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
