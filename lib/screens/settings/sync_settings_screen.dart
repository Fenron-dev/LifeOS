import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sync_provider.dart';
import '../../services/sync_client.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _pskCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pskCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop =
        Platform.isLinux || Platform.isWindows || Platform.isMacOS;

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(
        children: [
          // ── Server section (Desktop only) ─────────────────────────────────
          if (isDesktop) ...[
            const ListTile(
              dense: true,
              title: Text('Server',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            _ServerSection(),
            const Divider(),
          ],

          // ── Client section ────────────────────────────────────────────────
          const ListTile(
            dense: true,
            title: Text('Verbindung zu Desktop',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          _ClientSection(),
          const Divider(),

          // ── Sync now ─────────────────────────────────────────────────────
          const ListTile(
            dense: true,
            title: Text('Synchronisieren',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          _SyncNowSection(),

          // ── Info ──────────────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Die Synchronisation überträgt Ereignisse (Käufe, Verbrauch, '
              'Zustände) zwischen Desktop-Vault und Android.\n\n'
              'Desktop = Server · Android = Client\n'
              'Beide Geräte müssen im gleichen WLAN sein.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Server section (Desktop) ──────────────────────────────────────────────────

class _ServerSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(syncServerSettingsProvider);

    return settingsAsync.when(
      loading: () => const ListTile(title: Text('Lädt…')),
      error: (e, _) => ListTile(title: Text('Fehler: $e')),
      data: (settings) => Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Server aktivieren'),
            subtitle: Text('Port ${settings.port}'),
            value: settings.enabled,
            onChanged: (v) => ref
                .read(syncServerSettingsProvider.notifier)
                .setEnabled(v),
          ),
          if (settings.enabled) ...[
            _IpAddressTile(port: settings.port),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('PSK (Schlüssel)'),
              subtitle: Text(
                settings.psk,
                style: const TextStyle(
                    fontFamily: 'monospace', letterSpacing: 2),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Kopieren',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: settings.psk));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PSK kopiert')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Neu generieren',
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('PSK erneuern?'),
                          content: const Text(
                              'Der aktuelle Schlüssel wird ungültig. '
                              'Android-Geräte müssen neu verbunden werden.'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(false),
                                child: const Text('Abbrechen')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(true),
                                child: const Text('Erneuern')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        ref
                            .read(syncServerSettingsProvider.notifier)
                            .regeneratePsk();
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IpAddressTile extends StatelessWidget {
  final int port;
  const _IpAddressTile({required this.port});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: getLocalIpAddresses(),
      builder: (context, snap) {
        final ips = snap.data ?? [];
        final subtitle = ips.isEmpty
            ? 'Keine Netzwerkverbindung'
            : ips.map((ip) => 'http://$ip:$port').join('\n');
        return ListTile(
          leading: const Icon(Icons.wifi_outlined),
          title: const Text('Server-Adresse'),
          subtitle: Text(subtitle),
        );
      },
    );
  }
}

// ── Client section ────────────────────────────────────────────────────────────

class _ClientSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ClientSection> createState() => _ClientSectionState();
}

class _ClientSectionState extends ConsumerState<_ClientSection> {
  final _urlCtrl = TextEditingController();
  final _pskCtrl = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pskCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(syncClientSettingsProvider);
    return settingsAsync.when(
      loading: () => const ListTile(title: Text('Lädt…')),
      error: (e, _) => ListTile(title: Text('Fehler: $e')),
      data: (settings) {
        if (!_loaded) {
          _urlCtrl.text = settings.serverUrl;
          _pskCtrl.text = settings.psk;
          _loaded = true;
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Server-URL',
                  hintText: 'http://192.168.1.100:7070',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _pskCtrl,
                decoration: const InputDecoration(
                  labelText: 'PSK (Schlüssel)',
                  hintText: 'Vom Desktop kopieren',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      await ref
                          .read(syncClientSettingsProvider.notifier)
                          .save(
                              serverUrl: _urlCtrl.text.trim(),
                              psk: _pskCtrl.text.trim());
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                        const SnackBar(content: Text('Gespeichert')),
                      );
                    },
                    child: const Text('Speichern'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wifi_find_outlined, size: 18),
                    label: const Text('Testen'),
                    onPressed: () => _ping(context),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _ping(BuildContext context) async {
    final url = _urlCtrl.text.trim();
    final psk = _pskCtrl.text.trim();
    if (url.isEmpty || psk.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL und PSK eingeben')),
      );
      return;
    }
    final deviceId =
        await ref.read(syncDeviceIdProvider.future);
    final client = SyncClient(
        serverUrl: url, psk: psk, deviceId: deviceId);
    final error = await client.ping();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context); // ignore: use_build_context_synchronously
    final primary = Theme.of(context).colorScheme.primary; // ignore: use_build_context_synchronously
    final errorColor = Theme.of(context).colorScheme.error; // ignore: use_build_context_synchronously
    messenger.showSnackBar(SnackBar(
      content: Text(error == null ? 'Verbindung erfolgreich!' : 'Fehler: $error'),
      backgroundColor: error == null ? primary : errorColor,
    ));
  }
}

// ── Sync now section ──────────────────────────────────────────────────────────

class _SyncNowSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final syncAsync = ref.watch(syncOpsProvider);

    return Column(
      children: [
        ListTile(
          leading: syncAsync.isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          title: const Text('Jetzt synchronisieren'),
          subtitle: syncAsync.whenOrNull(
            data: (result) => result == null
                ? null
                : result.success
                    ? Text(
                        '${result.pushed} gesendet · ${result.pulled} empfangen',
                        style: TextStyle(color: cs.primary))
                    : Text(result.error ?? 'Fehler',
                        style: TextStyle(color: cs.error)),
          ),
          onTap: syncAsync.isLoading
              ? null
              : () => ref.read(syncOpsProvider.notifier).sync(),
        ),
      ],
    );
  }
}
