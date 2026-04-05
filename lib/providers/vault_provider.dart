import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/vault_manager.dart';
import '../db/database.dart';

const _kLastVaultKey = 'last_vault';
const _kRecentVaultsKey = 'recent_vaults';

// ---------------------------------------------------------------------------
// Current vault path — drives the whole app
// ---------------------------------------------------------------------------

final vaultPathProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Database — opened from current vault path
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase?>((ref) {
  final vaultPath = ref.watch(vaultPathProvider);
  if (vaultPath == null) return null;

  final db = AppDatabase(vaultPath);
  ref.onDispose(() => db.close());
  return db;
});

// ---------------------------------------------------------------------------
// Recent vaults (persisted via SharedPreferences)
// ---------------------------------------------------------------------------

final recentVaultsProvider =
    AsyncNotifierProvider<RecentVaultsNotifier, List<VaultInfo>>(
  RecentVaultsNotifier.new,
);

class RecentVaultsNotifier extends AsyncNotifier<List<VaultInfo>> {
  @override
  Future<List<VaultInfo>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kRecentVaultsKey) ?? [];
    return raw
        .map((s) {
          try {
            return VaultInfo.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<VaultInfo>()
        .toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
  }

  Future<void> addVault(String vaultPath) async {
    final info = VaultInfo(
      path: vaultPath,
      name: VaultManager.vaultName(vaultPath),
      lastOpened: DateTime.now(),
    );
    final current = state.valueOrNull ?? [];
    final updated = [
      info,
      ...current.where((v) => v.path != vaultPath),
    ].take(10).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kRecentVaultsKey,
      updated.map((v) => jsonEncode(v.toJson())).toList(),
    );
    await prefs.setString(_kLastVaultKey, vaultPath);
    state = AsyncData(updated);
  }
}

// ---------------------------------------------------------------------------
// Last used vault path (for auto-open on startup)
// ---------------------------------------------------------------------------

final lastVaultPathProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLastVaultKey);
});

// ---------------------------------------------------------------------------
// Device ID — stable UUID for sync/event attribution
// ---------------------------------------------------------------------------

const _kDeviceIdKey = 'device_id';

final deviceIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kDeviceIdKey);
  if (existing != null) return existing;
  final id = const Uuid().v4();
  await prefs.setString(_kDeviceIdKey, id);
  return id;
});
