import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'vault_provider.dart';

// ---------------------------------------------------------------------------
// App-wide settings (stored in AppSettings table inside the vault DB)
// ---------------------------------------------------------------------------

class AppSettingsData {
  final ThemeMode themeMode;
  final Locale locale;

  const AppSettingsData({
    this.themeMode = ThemeMode.system,
    this.locale = const Locale('de'),
  });

  AppSettingsData copyWith({ThemeMode? themeMode, Locale? locale}) =>
      AppSettingsData(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
      );
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettingsData>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<AppSettingsData> {
  @override
  Future<AppSettingsData> build() async {
    final db = ref.watch(databaseProvider);
    if (db == null) return const AppSettingsData();

    final themeRaw = await db.getSetting('theme_mode') ?? 'system';
    final localeRaw = await db.getSetting('locale') ?? 'de';

    return AppSettingsData(
      themeMode: switch (themeRaw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: Locale(localeRaw),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    final key = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await db.setSetting('theme_mode', key);
    state = AsyncData(state.valueOrNull?.copyWith(themeMode: mode) ??
        AppSettingsData(themeMode: mode));
  }

  Future<void> setLocale(Locale locale) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('locale', locale.languageCode);
    state = AsyncData(state.valueOrNull?.copyWith(locale: locale) ??
        AppSettingsData(locale: locale));
  }
}
