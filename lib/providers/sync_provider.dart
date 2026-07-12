import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import '../services/secret_storage.dart';
import '../services/sync_client.dart';
import '../services/sync_server.dart';
import 'vault_provider.dart';

// ── Keys ─────────────────────────────────────────────────────────────────────

const _kServerEnabled = 'sync_server_enabled';
const _kServerPort = 'sync_server_port';
// PSKs live in SecretStorage (Keychain/Keystore/libsecret) — S2. The literal
// values double as the legacy SharedPreferences keys for one-time migration.
const _kServerPsk = 'sync_server_psk';
const _kClientUrl = 'sync_client_url';
const _kClientPsk = 'sync_client_psk';

// Device-ID: bewusst KEIN eigener Provider — Events werden mit
// deviceIdProvider (vault_provider, Prefs-Key 'device_id') geschrieben.
// Ein zweiter Schlüssel hier führte dazu, dass der Push-Filter
// (e.deviceId == eigene ID) nie ein Event fand → Bestand synchronisierte nie.

// ── Server settings ───────────────────────────────────────────────────────────

class SyncServerSettings {
  final bool enabled;
  final int port;
  final String psk;

  const SyncServerSettings({
    required this.enabled,
    required this.port,
    required this.psk,
  });

  SyncServerSettings copyWith({bool? enabled, int? port, String? psk}) =>
      SyncServerSettings(
        enabled: enabled ?? this.enabled,
        port: port ?? this.port,
        psk: psk ?? this.psk,
      );
}

final syncServerSettingsProvider =
    AsyncNotifierProvider<SyncServerSettingsNotifier, SyncServerSettings>(
        SyncServerSettingsNotifier.new);

class SyncServerSettingsNotifier
    extends AsyncNotifier<SyncServerSettings> {
  @override
  Future<SyncServerSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    // Secure storage first; migrates a legacy plaintext PSK automatically.
    var psk =
        await SecretStorage.read(_kServerPsk, legacyPrefsKey: _kServerPsk);
    if (psk == null) {
      psk = _generatePsk();
      await SecretStorage.write(_kServerPsk, psk);
    }
    return SyncServerSettings(
      enabled: prefs.getBool(_kServerEnabled) ?? false,
      port: prefs.getInt(_kServerPort) ?? 7070,
      psk: psk,
    );
  }

  Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kServerEnabled, v);
    state = AsyncData((await future).copyWith(enabled: v));
  }

  Future<void> setPort(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kServerPort, v);
    state = AsyncData((await future).copyWith(port: v));
  }

  Future<void> regeneratePsk() async {
    final psk = _generatePsk();
    await SecretStorage.write(_kServerPsk, psk);
    state = AsyncData((await future).copyWith(psk: psk));
  }

  /// 12 chars from a 32-char alphabet ≈ 60 bit — combined with the per-IP
  /// rate limiter this is out of brute-force reach on a LAN.
  static String _generatePsk() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

// ── Active server lifecycle ───────────────────────────────────────────────────

/// Keeps a [SyncServer] running whenever the settings say so (Desktop only).
/// Disposing the provider stops the server.
final syncServerProvider = Provider<SyncServer?>((ref) {
  if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
    return null;
  }
  final settings = ref.watch(syncServerSettingsProvider).valueOrNull;
  final db = ref.watch(databaseProvider);
  final deviceId = ref.watch(deviceIdProvider).valueOrNull;
  if (settings == null || !settings.enabled || db == null || deviceId == null) {
    return null;
  }
  final server = SyncServer(
    db: db,
    psk: settings.psk,
    port: settings.port,
    deviceId: deviceId,
  );
  server.start().ignore();
  ref.onDispose(() => server.stop().ignore());
  return server;
});

// ── Client settings ───────────────────────────────────────────────────────────

class SyncClientSettings {
  final String serverUrl;
  final String psk;

  const SyncClientSettings({required this.serverUrl, required this.psk});

  SyncClientSettings copyWith({String? serverUrl, String? psk}) =>
      SyncClientSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        psk: psk ?? this.psk,
      );

  bool get isConfigured => serverUrl.isNotEmpty && psk.isNotEmpty;
}

final syncClientSettingsProvider =
    AsyncNotifierProvider<SyncClientSettingsNotifier, SyncClientSettings>(
        SyncClientSettingsNotifier.new);

class SyncClientSettingsNotifier
    extends AsyncNotifier<SyncClientSettings> {
  @override
  Future<SyncClientSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return SyncClientSettings(
      serverUrl: prefs.getString(_kClientUrl) ?? '',
      psk: await SecretStorage.read(_kClientPsk,
              legacyPrefsKey: _kClientPsk) ??
          '',
    );
  }

  Future<void> save({required String serverUrl, required String psk}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kClientUrl, serverUrl);
    await SecretStorage.write(_kClientPsk, psk);
    state = AsyncData(SyncClientSettings(serverUrl: serverUrl, psk: psk));
  }
}

// ── Sync operations ───────────────────────────────────────────────────────────

/// Result of a sync run.
class SyncResult {
  final int pushed; // rows the server applied from our push
  final int pulled; // rows we applied from the server's dump
  final String? error;

  const SyncResult({this.pushed = 0, this.pulled = 0, this.error});
  bool get success => error == null;
}

final syncOpsProvider =
    AsyncNotifierProvider<SyncOpsNotifier, SyncResult?>(SyncOpsNotifier.new);

class SyncOpsNotifier extends AsyncNotifier<SyncResult?> {
  @override
  Future<SyncResult?> build() async => null;

  Future<SyncResult> sync() async {
    state = const AsyncLoading();
    final result = await _run();
    state = AsyncData(result);
    return result;
  }

  Future<SyncResult> _run() async {
    final db = ref.read(databaseProvider);
    if (db == null) return const SyncResult(error: 'Kein Vault geöffnet');
    final deviceId = await ref.read(deviceIdProvider.future);
    final clientSettings =
        await ref.read(syncClientSettingsProvider.future);
    if (!clientSettings.isConfigured) {
      return const SyncResult(error: 'Kein Server konfiguriert');
    }

    final client = SyncClient(
      serverUrl: clientSettings.serverUrl,
      psk: clientSettings.psk,
      deviceId: deviceId,
    );

    try {
      final pingError = await client.ping();
      if (pingError != null) {
        return SyncResult(error: 'Server nicht erreichbar: $pingError');
      }

      // Full two-way sync: pull the server's dump and apply it, then push
      // ours. Every user table travels (see SyncDao.syncTableNames); LWW on
      // updated_at tables, insert-or-ignore for the rest. item_states is
      // rebuilt from inventory_entries on both sides.
      final remote = await client.pullFull();
      final pulled = await db.importFromSync(remote);

      final localDump = await db.exportForSync();
      final pushed = await client.pushFull(localDump);

      return SyncResult(pushed: pushed, pulled: pulled);
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }
}

// ── Auto-Sync ─────────────────────────────────────────────────────────────────

/// Side-effect provider: when a sync server is configured, syncs shortly
/// after vault open and every 15 minutes while the app runs. Failures are
/// silent — the last result stays visible in the sync settings.
final autoSyncProvider = Provider<void>((ref) {
  final db = ref.watch(databaseProvider);
  final client = ref.watch(syncClientSettingsProvider).valueOrNull;
  if (db == null || client == null || !client.isConfigured) return;

  Future<void> run() async {
    try {
      await ref.read(syncOpsProvider.notifier).sync();
    } catch (_) {/* silent — status visible in settings */}
  }

  final startTimer = Timer(const Duration(seconds: 10), run);
  final periodic =
      Timer.periodic(const Duration(minutes: 15), (_) => run());
  ref.onDispose(() {
    startTimer.cancel();
    periodic.cancel();
  });
});

// ── Local network IP addresses ────────────────────────────────────────────────

/// Returns all non-loopback IPv4 addresses for the server URL display.
Future<List<String>> getLocalIpAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLinkLocal: false);
    return interfaces
        .expand((i) => i.addresses)
        .where((a) => !a.isLoopback)
        .map((a) => a.address)
        .toList();
  } catch (_) {
    return [];
  }
}
