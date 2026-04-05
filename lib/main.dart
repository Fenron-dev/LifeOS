import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_localizations.dart';

import 'core/vault_manager.dart';
import 'services/notification_service.dart';
import 'providers/settings_provider.dart';
import 'providers/vault_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
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
  }

  Future<void> _tryAutoOpenLastVault() async {
    final lastPath = await ref.read(lastVaultPathProvider.future);
    if (lastPath == null) return;
    if (!Directory(lastPath).existsSync()) return;

    final ok = await VaultManager.initializeVault(lastPath);
    if (!ok) return;

    ref.read(vaultPathProvider.notifier).state = lastPath;
    ref.read(recentVaultsProvider.notifier).addVault(lastPath);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;

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
