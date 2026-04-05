import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/vault_manager.dart';
import '../../providers/vault_provider.dart';

class VaultSelectionScreen extends ConsumerWidget {
  const VaultSelectionScreen({super.key});

  // On Android/iOS, FilePicker returns a content URI (SAF), not a real
  // filesystem path — SQLite cannot open such URIs (error 14).
  // Mobile always uses the app's documents directory as vault location.
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentVaultsProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.home, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'LifeOS',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wähle einen Vault um zu beginnen',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 40),
                  // On mobile: single button uses default path (always writable).
                  // On desktop: offer both default and custom folder.
                  FilledButton.icon(
                    onPressed: () => _createDefaultVault(context, ref),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: Text(_isMobile
                        ? 'Vault erstellen'
                        : 'Standard-Vault erstellen'),
                  ),
                  if (!_isMobile) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _pickVault(context, ref),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Ordner auswählen'),
                    ),
                  ],
                  const SizedBox(height: 32),
                  recentAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, st) => const SizedBox.shrink(),
                    data: (recents) {
                      if (recents.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Zuletzt geöffnet',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          ...recents.map((v) => _RecentVaultTile(
                                vault: v,
                                onTap: () => _activateVault(context, ref, v.path),
                              )),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Creates (or opens) the vault at the platform default location.
  /// On Android this is always inside the app sandbox — guaranteed writable.
  Future<void> _createDefaultVault(BuildContext context, WidgetRef ref) async {
    final path = await VaultManager.defaultVaultPath();
    if (!context.mounted) return;
    await _activateVault(context, ref, path);
  }

  /// Desktop only: let the user pick any folder via the system dialog.
  Future<void> _pickVault(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Vault-Ordner auswählen oder erstellen',
    );
    if (result == null || !context.mounted) return;
    await _activateVault(context, ref, result);
  }

  Future<void> _activateVault(
      BuildContext context, WidgetRef ref, String path) async {
    final ok = await VaultManager.initializeVault(path);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vault konnte nicht erstellt werden.')),
      );
      return;
    }
    await ref.read(recentVaultsProvider.notifier).addVault(path);
    ref.read(vaultPathProvider.notifier).state = path;
  }
}

class _RecentVaultTile extends StatelessWidget {
  final VaultInfo vault;
  final VoidCallback onTap;

  const _RecentVaultTile({required this.vault, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final exists = Directory(vault.path).existsSync();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.folder,
          color: exists ? null : Theme.of(context).colorScheme.error,
        ),
        title: Text(vault.name),
        subtitle: Text(
          vault.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: exists ? null : const Icon(Icons.warning_amber_outlined),
        onTap: exists ? onTap : null,
      ),
    );
  }
}
