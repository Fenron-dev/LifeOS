import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/vault_key.dart';
import '../../core/vault_manager.dart';
import '../../core/vault_metadata.dart';
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
                  // Desktop: creating ALWAYS asks for the storage location
                  // (system folder picker). Mobile: app documents dir — SAF
                  // content-URIs kann SQLite nicht öffnen.
                  FilledButton.icon(
                    onPressed: () => _isMobile
                        ? _createDefaultVault(context, ref)
                        : _pickVault(context, ref),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: Text(_isMobile
                        ? 'Vault erstellen'
                        : 'Vault erstellen / öffnen — Ordner wählen'),
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
                                onTap: () =>
                                    _activateVault(context, ref, v.path),
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

    // Brand-new vault → ask the user how to encrypt it. Existing vault → load
    // metadata and (for password mode) prompt for the password.
    var metadata = await VaultMetadata.load(path);
    if (!context.mounted) return;
    String? key;
    if (metadata == null) {
      final choice = await _askEncryptionChoice(context);
      if (!context.mounted || choice == null) return;
      try {
        final init = await VaultKeyService.initializeForNewVault(
          vaultPath: path,
          mode: choice.mode,
          password: choice.password,
        );
        metadata = init.metadata;
        key = init.key;
        await metadata.save(path);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verschlüsselung fehlgeschlagen: $e')),
        );
        return;
      }
    } else {
      try {
        if (metadata.encryption == VaultEncryptionMode.password) {
          final pw = await _askPassword(context);
          if (!context.mounted || pw == null) return;
          key = await VaultKeyService.resolveKey(
            vaultPath: path,
            metadata: metadata,
            password: pw,
          );
        } else {
          key = await VaultKeyService.resolveKey(
            vaultPath: path,
            metadata: metadata,
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vault konnte nicht entschlüsselt werden: $e')),
        );
        return;
      }
    }

    await ref.read(recentVaultsProvider.notifier).addVault(path);
    ref.read(openVaultProvider.notifier).state = OpenVault(
      path: path,
      metadata: metadata,
      key: key,
    );
  }

  // ── Dialogs ──────────────────────────────────────────────────────────────

  Future<_EncryptionChoice?> _askEncryptionChoice(BuildContext context) {
    return showDialog<_EncryptionChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _EncryptionChoiceDialog(),
    );
  }

  Future<String?> _askPassword(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PasswordPromptDialog(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Encryption choice (new vault)
// ─────────────────────────────────────────────────────────────────────────────

class _EncryptionChoice {
  final VaultEncryptionMode mode;
  final String? password;
  const _EncryptionChoice(this.mode, [this.password]);
}

class _EncryptionChoiceDialog extends StatefulWidget {
  const _EncryptionChoiceDialog();

  @override
  State<_EncryptionChoiceDialog> createState() =>
      _EncryptionChoiceDialogState();
}

class _EncryptionChoiceDialogState extends State<_EncryptionChoiceDialog> {
  VaultEncryptionMode _mode = VaultEncryptionMode.keystore;
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_mode == VaultEncryptionMode.password) {
      final pw = _pwCtrl.text;
      if (pw.length < 8) {
        setState(() => _error = 'Passwort muss mindestens 8 Zeichen lang sein');
        return;
      }
      if (pw != _pwConfirmCtrl.text) {
        setState(() => _error = 'Passwörter stimmen nicht überein');
        return;
      }
      Navigator.of(context).pop(_EncryptionChoice(_mode, pw));
      return;
    }
    Navigator.of(context).pop(_EncryptionChoice(_mode));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vault-Verschlüsselung'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Wie soll dieser Vault gesichert werden? Photos liegen weiter '
              'unverschlüsselt im Ordner — nur die Datenbank wird verschlüsselt.',
            ),
            const SizedBox(height: 16),
            RadioGroup<VaultEncryptionMode>(
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
              child: Column(
                children: [
                  RadioListTile<VaultEncryptionMode>(
                    value: VaultEncryptionMode.keystore,
                    title: const Text('OS-Schlüsselbund (empfohlen)'),
                    subtitle: const Text(
                      'Bequem, kein Passwort-Prompt. Schlüssel bleibt auf diesem '
                      'Gerät — beim Kopieren des Vaults muss neu gepairt werden.',
                    ),
                  ),
                  RadioListTile<VaultEncryptionMode>(
                    value: VaultEncryptionMode.password,
                    title: const Text('Passwort'),
                    subtitle: const Text(
                      'Sicherer und vollständig portabel. Wird bei jedem App-Start '
                      'abgefragt.',
                    ),
                  ),
                  RadioListTile<VaultEncryptionMode>(
                    value: VaultEncryptionMode.none,
                    title: const Text('Keine Verschlüsselung'),
                    subtitle: const Text('Nur für Tests / unkritische Daten.'),
                  ),
                ],
              ),
            ),
            if (_mode == VaultEncryptionMode.password) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _pwCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Passwort (min. 8 Zeichen)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pwConfirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Passwort wiederholen',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Vault erstellen'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Password prompt (existing password-protected vault)
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog();

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vault entsperren'),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Passwort',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Entsperren'),
        ),
      ],
    );
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
