import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';
import '../../services/backup_service.dart';
import '../../services/data_export_service.dart';

Future<void> _showQuickActionsConfig(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider).valueOrNull;
  if (settings == null) return;
  final selected = Set<QuickAction>.from(settings.quickActions);
  final l10n = AppLocalizations.of(context);

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Schnellaktionen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: QuickAction.values.map((a) => CheckboxListTile(
            value: selected.contains(a),
            title: Row(children: [
              Icon(a.icon, size: 20),
              const SizedBox(width: 8),
              Text(a.label(l10n)),
            ]),
            onChanged: (v) => setState(() {
              if (v == true) { selected.add(a); } else { selected.remove(a); }
            }),
            dense: true,
          )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).setQuickActions(
                QuickAction.values.where(selected.contains).toList(),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final vaultPath = ref.watch(vaultPathProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        children: [
          // Vault info
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Aktiver Vault'),
            subtitle: Text(
              vaultPath ?? '–',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(openVaultProvider.notifier).state = null,
              child: const Text('Wechseln'),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Lagerorte'),
            subtitle: const Text('Kühlschrank, Keller, Regal…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/locations'),
          ),
          ListTile(
            leading: const Icon(Icons.store_outlined),
            title: const Text('Geschäfte'),
            subtitle: const Text('Supermärkte, Läden…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/shops'),
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('Einheiten'),
            subtitle: const Text('Namen anpassen, eigene hinzufügen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/units'),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Einheiten-Umrechnung'),
            subtitle: const Text('Globale Regeln: 1 kg = 1000 g…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/unit-conversions'),
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_outlined),
            title: const Text('Mahlzeiten'),
            subtitle: const Text('Frühstück, Mittag, Abendessen, Snacks…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/meal-types'),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Eigene Kategorien'),
            subtitle: const Text('Fitness, Mealprep, Babynahrung…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/categories'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Templates'),
            subtitle: const Text('Felder-Vorlagen für Artikel (Laptop, Gerät…)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/templates'),
          ),
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Produkttypen'),
            subtitle: const Text('Eigene Typen anlegen und verwalten'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/product-types'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Automation'),
            subtitle: const Text('If→Then Regeln für automatische Aufgaben'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/automation'),
          ),
          const Divider(),
          // ── Benachrichtigungen ──────────────────────────────────────────
          const ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Benachrichtigungen'),
            dense: true,
            enabled: false,
          ),
          settingsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (settings) => _WaterReminderTile(settings: settings),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Hilfe & Anleitung'),
            subtitle: const Text('Alle Funktionen erklärt'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/help'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.backup_outlined),
            title: Text('Datensicherung'),
            dense: true,
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: const Text('Backup erstellen'),
            subtitle: const Text('Vault als ZIP exportieren'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _createBackup(context, ref, vaultPath),
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Backup wiederherstellen'),
            subtitle: const Text('ZIP auswählen und einspielen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _restoreBackup(context, ref, vaultPath),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.import_export_outlined),
            title: Text('Daten-Export / Import'),
            dense: true,
            enabled: false,
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Daten exportieren'),
            subtitle: const Text('JSON ohne Fotos – vault-übergreifend nutzbar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportData(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Daten importieren'),
            subtitle: const Text('JSON-Export einspielen (upsert)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _importData(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Gesundheitsdaten als CSV'),
            subtitle: const Text('Gewicht, Ernährung, Körpermaße exportieren'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportHealthCsv(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Schnellaktionen'),
            subtitle: const Text('Aktionen im zentralen Button'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showQuickActionsConfig(context, ref),
          ),
          const Divider(),
          // Theme
          settingsAsync.when(
            loading: () => const ListTile(title: Text('Lädt…')),
            error: (e, _) => ListTile(title: Text('Fehler: $e')),
            data: (settings) => ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Design'),
              trailing: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('Systemstandard'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Hell'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text('Dunkel'),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(settingsProvider.notifier).setThemeMode(mode);
                  }
                },
              ),
            ),
          ),
          // Language
          settingsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (settings) => ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Sprache'),
              trailing: DropdownButton<Locale>(
                value: settings.locale,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: Locale('de'),
                    child: Text('Deutsch'),
                  ),
                  DropdownMenuItem(
                    value: Locale('en'),
                    child: Text('English'),
                  ),
                ],
                onChanged: (locale) {
                  if (locale != null) {
                    ref.read(settingsProvider.notifier).setLocale(locale);
                  }
                },
              ),
            ),
          ),
          const Divider(),
          const ListTile(
            dense: true,
            title: Text('Darstellung',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          settingsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (settings) => Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.text_fields),
                  title: const Text('Automatische Schriftgröße'),
                  subtitle: const Text(
                      'Text wird verkleinert statt abgeschnitten'),
                  value: settings.autoSizeText,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setAutoSizeText(v),
                ),
                if (settings.autoSizeText)
                  _CountSettingTile(
                    icon: Icons.format_size,
                    title: 'Max. Verkleinerung',
                    subtitle: 'Schritte à 2pt (1 = −2pt, 2 = −4pt, 3 = −6pt)',
                    value: settings.maxSizeReduction,
                    options: const [1, 2, 3],
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setMaxSizeReduction(v),
                  ),
              ],
            ),
          ),
          const Divider(),
          const ListTile(
            dense: true,
            title: Text('Tagebuch – Verlauf',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          settingsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (settings) => Column(
              children: [
                _CountSettingTile(
                  icon: Icons.history,
                  title: 'Kürzlich gegessen',
                  subtitle: 'Einträge im "Kürzlich"-Tab',
                  value: settings.historyRecentCount,
                  options: const [10, 20, 30, 50],
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setHistoryRecentCount(v),
                ),
                _CountSettingTile(
                  icon: Icons.trending_up,
                  title: 'Häufig gegessen',
                  subtitle: 'Einträge im "Häufig"-Tab',
                  value: settings.historyFrequentCount,
                  options: const [10, 20, 30, 50],
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setHistoryFrequentCount(v),
                ),
                _CountSettingTile(
                  icon: Icons.restaurant_menu,
                  title: 'Alle Mahlzeiten',
                  subtitle: 'Einträge in der "Alle Mahlzeiten"-Sektion',
                  value: settings.historyAllMealsCount,
                  options: const [5, 10, 20, 30],
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setHistoryAllMealsCount(v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Water reminder settings tile ──────────────────────────────────────────────

class _WaterReminderTile extends ConsumerWidget {
  final AppSettingsData settings;
  const _WaterReminderTile({required this.settings});

  String _fmtHour(int h) => '${h.toString().padLeft(2, '0')}:00';

  String _fmtInterval(int min) {
    if (min < 60) return 'alle $min Min.';
    if (min % 60 == 0) return 'alle ${min ~/ 60} Std.';
    return 'alle ${(min / 60).toStringAsFixed(1)} Std.';
  }

  Future<void> _pickWindow(BuildContext context, WidgetRef ref) async {
    final from = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.waterReminderFromHour, minute: 0),
      helpText: 'Von (Startzeit)',
    );
    if (from == null || !context.mounted) return;
    final to = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: settings.waterReminderToHour, minute: 0),
      helpText: 'Bis (Endzeit)',
    );
    if (to == null || !context.mounted) return;
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setWaterReminderFromHour(from.hour);
    await notifier.setWaterReminderToHour(to.hour);
  }

  Future<void> _pickInterval(BuildContext context, WidgetRef ref) async {
    const options = [30, 60, 90, 120, 180];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Erinnerungsintervall'),
        children: options
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(m),
                  child: Text(
                    m < 60
                        ? 'Alle $m Minuten'
                        : m % 60 == 0
                            ? 'Alle ${m ~/ 60} Stunden'
                            : 'Alle ${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')} Std.',
                    style: TextStyle(
                      fontWeight: m == settings.waterReminderIntervalMinutes
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
    if (picked != null && context.mounted) {
      await ref.read(settingsProvider.notifier).setWaterReminderIntervalMinutes(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.water_drop_outlined),
          title: const Text('Wasserreminder'),
          subtitle: const Text('Push-Hinweis wenn Ziel nicht erreicht'),
          value: settings.waterReminderEnabled,
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setWaterReminderEnabled(v),
        ),
        if (settings.waterReminderEnabled) ...[
          ListTile(
            leading: const SizedBox.shrink(),
            title: const Text('Zeitfenster'),
            subtitle: Text(
                '${_fmtHour(settings.waterReminderFromHour)} – ${_fmtHour(settings.waterReminderToHour)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickWindow(context, ref),
          ),
          ListTile(
            leading: const SizedBox.shrink(),
            title: const Text('Interval'),
            subtitle: Text(_fmtInterval(settings.waterReminderIntervalMinutes)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickInterval(context, ref),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CountSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _CountSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: DropdownButton<int>(
          value: options.contains(value) ? value : options.first,
          underline: const SizedBox.shrink(),
          items: options
              .map((n) =>
                  DropdownMenuItem(value: n, child: Text('$n Einträge')))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      );
}

Future<void> _createBackup(
    BuildContext context, WidgetRef ref, String? vaultPath) async {
  if (vaultPath == null) return;
  try {
    final tmpDir = await getTemporaryDirectory();
    final backup = await BackupService.createBackup(vaultPath, tmpDir.path);
    if (!context.mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(backup.path)],
      subject: 'LifeOS Backup',
    ));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backup fehlgeschlagen: $e')),
    );
  }
}

Future<void> _restoreBackup(
    BuildContext context, WidgetRef ref, String? vaultPath) async {
  if (vaultPath == null) return;

  // Step 1: Pick the backup file
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  if (result == null || result.files.single.path == null) return;
  if (!context.mounted) return;

  final zipPath = result.files.single.path!;

  // Step 2: Analyse the zip
  int zipFileCount = 0;
  bool hasDb = false;
  String? backupDateStr;
  try {
    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeBuffer(input);
    for (final f in archive) {
      if (f.isFile) {
        zipFileCount++;
        final name = p.basename(f.name);
        if (name == 'lifeos.db') hasDb = true;
      }
    }
    await input.close();
    final fname = p.basename(zipPath);
    final m = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(fname);
    if (m != null) backupDateStr = m.group(1);
  } catch (_) {}

  if (!context.mounted) return;
  if (!hasDb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Ungültiges Backup: lifeos.db nicht gefunden.')),
    );
    return;
  }

  // Step 3: Count current DB contents for comparison
  final db = ref.read(databaseProvider);
  int currentItems = 0;
  int currentEntries = 0;
  if (db != null) {
    try {
      final r1 =
          await db.customSelect('SELECT COUNT(*) AS c FROM items').getSingle();
      currentItems = r1.read<int>('c');
      final r2 = await db
          .customSelect('SELECT COUNT(*) AS c FROM inventory_entries')
          .getSingle();
      currentEntries = r2.read<int>('c');
    } catch (_) {}
  }
  if (!context.mounted) return;

  // Step 4: Confirmation with stats
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Backup wiederherstellen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (backupDateStr != null)
            Text('Backup vom $backupDateStr',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('$zipFileCount Dateien im Backup'),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          Text('Dein aktueller Vault: $currentItems Artikel, '
              '$currentEntries Buchungen'),
          const SizedBox(height: 8),
          const Text(
            'Alle aktuellen Daten werden überschrieben. '
            'Nicht gesicherte Änderungen gehen dauerhaft verloren.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Wiederherstellen'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  // Step 5: Restore
  try {
    await ref.read(databaseProvider)?.close();
    await BackupService.restoreBackup(zipPath, vaultPath);
    if (!context.mounted) return;
    ref.invalidate(databaseProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup erfolgreich eingespielt')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Wiederherstellung fehlgeschlagen: $e')),
    );
  }
}

Future<void> _exportData(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  if (db == null) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Daten exportieren'),
      content: const Text(
        'Die Export-Datei enthält persönliche Gesundheitsdaten '
        '(Gewicht, Ernährung, Maße, Aufgaben).\n\n'
        'Bewahre sie sicher auf und teile sie nur mit vertrauenswürdigen Empfängern.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exportieren')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  try {
    final tmpDir = await getTemporaryDirectory();
    final file = await DataExportService.exportData(db, tmpDir.path);
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'LifeOS Daten-Export',
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export fehlgeschlagen: $e')),
    );
  }
}

Future<void> _exportHealthCsv(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  if (db == null) return;
  try {
    final tmpDir = await getTemporaryDirectory();
    final file = await DataExportService.exportHealthCsv(db, tmpDir.path);
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'LifeOS Gesundheitsdaten CSV',
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV-Export fehlgeschlagen: $e')),
    );
  }
}

Future<void> _importData(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  if (db == null) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (result == null || result.files.single.path == null) return;
  if (!context.mounted) return;

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Daten importieren?'),
      content: const Text(
          'Vorhandene Datensätze werden überschrieben (gleiche IDs), '
          'neue werden hinzugefügt.\n\n'
          'Empfehlung: Erstelle vorher ein Backup, um den aktuellen '
          'Zustand sichern zu können.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Abbrechen')),
        OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('backup_first'),
            child: const Text('Backup + Import')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop('import'),
            child: const Text('Direkt importieren')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == 'backup_first') {
    final vaultPath = ref.read(vaultPathProvider);
    if (vaultPath != null && context.mounted) {
      try {
        final tmpDir = await getTemporaryDirectory();
        await BackupService.createBackup(vaultPath, tmpDir.path);
      } catch (_) {}
    }
    if (!context.mounted) return;
  }

  try {
    final importResult = await DataExportService.importData(
        db, result.files.single.path!);
    ref.invalidate(databaseProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '${importResult.totalRows} Datensätze importiert'
          '${importResult.skippedRows > 0 ? ', ${importResult.skippedRows} übersprungen' : ''}.'),
    ));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Import fehlgeschlagen: $e')),
    );
  }
}
