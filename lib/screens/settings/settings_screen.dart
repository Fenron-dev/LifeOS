import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';
import '../../services/backup_service.dart';

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
        ],
      ),
    );
  }
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

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Backup wiederherstellen?'),
      content: const Text(
          'Der aktuelle Vault wird durch das Backup überschrieben. Nicht gesicherte Daten gehen verloren.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Wiederherstellen'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  if (result == null || result.files.single.path == null) return;
  if (!context.mounted) return;

  try {
    // Close DB before overwriting
    await ref.read(databaseProvider)?.close();
    await BackupService.restoreBackup(result.files.single.path!, vaultPath);
    if (!context.mounted) return;
    // Reload vault
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
