import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../services/sync_client.dart';
import '../services/sync_server.dart';
import 'vault_provider.dart';

// ── Keys ─────────────────────────────────────────────────────────────────────

const _kServerEnabled = 'sync_server_enabled';
const _kServerPort = 'sync_server_port';
const _kServerPsk = 'sync_server_psk';
const _kDeviceId = 'sync_device_id';
const _kClientUrl = 'sync_client_url';
const _kClientPsk = 'sync_client_psk';

// ── Device ID ─────────────────────────────────────────────────────────────────

final syncDeviceIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(_kDeviceId);
  if (id == null) {
    id = const Uuid().v4();
    await prefs.setString(_kDeviceId, id);
  }
  return id;
});

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
    final psk = prefs.getString(_kServerPsk) ?? _generatePsk();
    if (!prefs.containsKey(_kServerPsk)) {
      await prefs.setString(_kServerPsk, psk);
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
    ref.invalidateSelf();
  }

  Future<void> setPort(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kServerPort, v);
    state = AsyncData((await future).copyWith(port: v));
    ref.invalidateSelf();
  }

  Future<void> regeneratePsk() async {
    final psk = _generatePsk();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerPsk, psk);
    state = AsyncData((await future).copyWith(psk: psk));
    ref.invalidateSelf();
  }

  static String _generatePsk() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
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
  final deviceId = ref.watch(syncDeviceIdProvider).valueOrNull;
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
      psk: prefs.getString(_kClientPsk) ?? '',
    );
  }

  Future<void> save({required String serverUrl, required String psk}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kClientUrl, serverUrl);
    await prefs.setString(_kClientPsk, psk);
    state = AsyncData(SyncClientSettings(serverUrl: serverUrl, psk: psk));
  }
}

// ── Sync operations ───────────────────────────────────────────────────────────

/// Result of a sync run.
class SyncResult {
  final int pushed;
  final int pulled;
  final String? error;

  const SyncResult({this.pushed = 0, this.pulled = 0, this.error});
  bool get success => error == null;
}

final syncOpsProvider =
    AsyncNotifierProvider<SyncOpsNotifier, SyncResult?>(SyncOpsNotifier.new);

class SyncOpsNotifier extends AsyncNotifier<SyncResult?> {
  @override
  Future<SyncResult?> build() async => null;

  AppDatabase get _db => ref.read(databaseProvider)!;

  Future<SyncResult> sync() async {
    state = const AsyncLoading();
    final deviceId =
        await ref.read(syncDeviceIdProvider.future);
    final clientSettings =
        await ref.read(syncClientSettingsProvider.future);

    if (!clientSettings.isConfigured) {
      final result =
          const SyncResult(error: 'Kein Server konfiguriert');
      state = AsyncData(result);
      return result;
    }

    final client = SyncClient(
      serverUrl: clientSettings.serverUrl,
      psk: clientSettings.psk,
      deviceId: deviceId,
    );

    try {
      // Ping
      final pingError = await client.ping();
      if (pingError != null) {
        final result = SyncResult(error: 'Server nicht erreichbar: $pingError');
        state = AsyncData(result);
        return result;
      }

      // Push: local events not yet synced
      final localEvents = await _db.getItemEventsSince(
        DateTime.fromMillisecondsSinceEpoch(0),
        excludeDeviceId: null, // push everything local
      );
      final myEvents = localEvents
          .where((e) => e.deviceId == deviceId && e.syncStatus != 'synced')
          .toList();
      final pushed = await client.pushEvents(myEvents);

      // Pull: events from server since our last sync
      final since = await _db.lastSyncedAt(localDeviceId: deviceId);
      final remoteJson = await client.pullEvents(since);
      final companions = remoteJson
          .map(SyncServer.jsonToCompanion)
          .toList();
      await _db.insertSyncedEvents(companions);

      final result = SyncResult(pushed: pushed, pulled: companions.length);
      state = AsyncData(result);
      return result;
    } catch (e) {
      final result = SyncResult(error: e.toString());
      state = AsyncData(result);
      return result;
    }
  }
}

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
