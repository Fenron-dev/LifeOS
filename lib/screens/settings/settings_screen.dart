import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/settings_provider.dart';
import '../../providers/vault_provider.dart';

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
                  ref.read(vaultPathProvider.notifier).state = null,
              child: const Text('Wechseln'),
            ),
          ),
          const Divider(),
          // Locations
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Lagerorte'),
            subtitle: const Text('Kühlschrank, Keller, Regal…'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/locations'),
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
