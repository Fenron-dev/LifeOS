import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/vault_manager.dart';
import '../../providers/vault_provider.dart';

class VaultSelectionScreen extends ConsumerWidget {
  const VaultSelectionScreen({super.key});

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
                  FilledButton.icon(
                    onPressed: () => _openVault(context, ref),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Vault öffnen'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _createVault(context, ref),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Neuer Vault'),
                  ),
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

  Future<void> _openVault(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Vault-Ordner auswählen',
    );
    if (result == null || !context.mounted) return;
    await _activateVault(context, ref, result);
  }

  Future<void> _createVault(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Neuen Vault-Ordner auswählen oder erstellen',
    );
    if (result == null || !context.mounted) return;
    await _activateVault(context, ref, result);
  }

  Future<void> _activateVault(
      BuildContext context, WidgetRef ref, String path) async {
    final ok = await VaultManager.initializeVault(path);
    if (!ok || !context.mounted) return;
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
