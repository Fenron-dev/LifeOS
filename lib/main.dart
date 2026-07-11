import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_localizations.dart';

import 'core/vault_key.dart';
import 'core/vault_manager.dart';
import 'core/vault_metadata.dart';
import 'db/sql_cipher_loader.dart';
import 'services/notification_service.dart';
import 'providers/auto_backup_provider.dart';
import 'providers/home_widget_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vault_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SqlCipherLoader.registerOpenOverride();
  // Don't block runApp() on notification init — on macOS the permission dialog
  // would appear before any Flutter widgets are painted (black screen).
  unawaited(NotificationService.initialize().catchError((_) {}));
  runApp(const ProviderScope(child: LifeOSApp()));
}

class LifeOSApp extends ConsumerStatefulWidget {
  const LifeOSApp({super.key});

  @override
  ConsumerState<LifeOSApp> createState() => _LifeOSAppState();
}

class _LifeOSAppState extends ConsumerState<LifeOSApp> {
  @override
  void initState() {
    super.initState();
    _tryAutoOpenLastVault();
    // Request macOS notification permission after the first frame so the
    // dialog appears over a rendered UI, not over a black screen.
    if (Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.requestMacOSPermission();
      });
    }
  }

  Future<void> _tryAutoOpenLastVault() async {
    final lastPath = await ref.read(lastVaultPathProvider.future);
    if (lastPath == null) return;
    if (!Directory(lastPath).existsSync()) return;

    final ok = await VaultManager.initializeVault(lastPath);
    if (!ok) return;

    // Password-protected vaults need a UI prompt — let the selection screen
    // handle them. We can only auto-open none/keystore modes (and legacy
    // unencrypted vaults without metadata).
    final metadata = await VaultMetadata.load(lastPath);
    if (metadata != null &&
        metadata.encryption == VaultEncryptionMode.password) {
      return;
    }

    String? key;
    try {
      if (metadata != null) {
        key = await VaultKeyService.resolveKey(
          vaultPath: lastPath,
          metadata: metadata,
        );
      }
    } catch (_) {
      return;
    }

    ref.read(openVaultProvider.notifier).state = OpenVault(
      path: lastPath,
      metadata: metadata ??
          VaultMetadata(
            version: 1,
            encryption: VaultEncryptionMode.none,
            createdAt: DateTime.now(),
          ),
      key: key,
    );
    ref.read(recentVaultsProvider.notifier).addVault(lastPath);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    // Keep side-effect providers alive as long as the app runs.
    ref.watch(expiryNotificationSchedulerProvider);
    ref.watch(homeWidgetUpdaterProvider);
    ref.watch(syncServerProvider); // starts shelf server when enabled (Desktop)
    ref.watch(autoBackupProvider); // runs due auto-backups (all platforms)

    return MaterialApp.router(
      title: 'LifeOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings?.themeMode ?? ThemeMode.system,
      locale: settings?.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
