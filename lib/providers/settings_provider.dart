import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'vault_provider.dart';

// ---------------------------------------------------------------------------
// Available quick actions
// ---------------------------------------------------------------------------

enum QuickAction {
  addInventory,
  consumeInventory,
  quickDeduct,
  addTask,
  addWishlist,
  addRecipe,
  scanBarcode,
}

extension QuickActionX on QuickAction {
  String get id => name;
  String label(AppLocalizations l10n) => switch (this) {
        QuickAction.addInventory => l10n.quickActionAddInventory,
        QuickAction.consumeInventory => l10n.quickActionConsumeInventory,
        QuickAction.quickDeduct => l10n.quickActionQuickDeduct,
        QuickAction.addTask => l10n.quickActionAddTask,
        QuickAction.addWishlist => l10n.quickActionAddWishlist,
        QuickAction.addRecipe => l10n.quickActionAddRecipe,
        QuickAction.scanBarcode => l10n.quickActionScanBarcode,
      };
  IconData get icon => switch (this) {
        QuickAction.addInventory => Icons.add_shopping_cart,
        QuickAction.consumeInventory => Icons.remove_shopping_cart,
        QuickAction.quickDeduct => Icons.bolt,
        QuickAction.addTask => Icons.add_task,
        QuickAction.addWishlist => Icons.favorite_border,
        QuickAction.addRecipe => Icons.menu_book_outlined,
        QuickAction.scanBarcode => Icons.qr_code_scanner,
      };
}

// ---------------------------------------------------------------------------
// App-wide settings (stored in AppSettings table inside the vault DB)
// ---------------------------------------------------------------------------

class AppSettingsData {
  final ThemeMode themeMode;
  final Locale locale;
  final List<QuickAction> quickActions;
  /// How many entries to show in the "Kürzlich gegessen" tab.
  final int historyRecentCount;
  /// How many entries to show in the "Häufig gegessen" tab.
  final int historyFrequentCount;
  /// How many cross-meal-type entries to show in the "Alle Mahlzeiten" section.
  final int historyAllMealsCount;

  static const defaultQuickActions = [
    QuickAction.addInventory,
    QuickAction.consumeInventory,
    QuickAction.addTask,
    QuickAction.addWishlist,
  ];

  const AppSettingsData({
    this.themeMode = ThemeMode.system,
    this.locale = const Locale('de'),
    this.quickActions = AppSettingsData.defaultQuickActions,
    this.historyRecentCount = 20,
    this.historyFrequentCount = 20,
    this.historyAllMealsCount = 10,
  });

  AppSettingsData copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    List<QuickAction>? quickActions,
    int? historyRecentCount,
    int? historyFrequentCount,
    int? historyAllMealsCount,
  }) =>
      AppSettingsData(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        quickActions: quickActions ?? this.quickActions,
        historyRecentCount: historyRecentCount ?? this.historyRecentCount,
        historyFrequentCount: historyFrequentCount ?? this.historyFrequentCount,
        historyAllMealsCount: historyAllMealsCount ?? this.historyAllMealsCount,
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

    final quickActionsRaw = await db.getSetting('quick_actions');
    final quickActions = quickActionsRaw != null
        ? (jsonDecode(quickActionsRaw) as List<dynamic>)
            .map((id) => QuickAction.values
                .where((a) => a.id == id)
                .firstOrNull)
            .whereType<QuickAction>()
            .toList()
        : AppSettingsData.defaultQuickActions;

    final historyRecentCount =
        int.tryParse(await db.getSetting('history_recent_count') ?? '') ?? 20;
    final historyFrequentCount =
        int.tryParse(await db.getSetting('history_frequent_count') ?? '') ?? 20;
    final historyAllMealsCount =
        int.tryParse(await db.getSetting('history_all_meals_count') ?? '') ?? 10;

    return AppSettingsData(
      themeMode: switch (themeRaw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: Locale(localeRaw),
      quickActions: quickActions,
      historyRecentCount: historyRecentCount,
      historyFrequentCount: historyFrequentCount,
      historyAllMealsCount: historyAllMealsCount,
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

  Future<void> setQuickActions(List<QuickAction> actions) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('quick_actions', jsonEncode(actions.map((a) => a.id).toList()));
    state = AsyncData(
        state.valueOrNull?.copyWith(quickActions: actions) ??
            AppSettingsData(quickActions: actions));
  }

  Future<void> setHistoryRecentCount(int count) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('history_recent_count', '$count');
    state = AsyncData(state.valueOrNull?.copyWith(historyRecentCount: count) ??
        AppSettingsData(historyRecentCount: count));
  }

  Future<void> setHistoryFrequentCount(int count) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('history_frequent_count', '$count');
    state = AsyncData(
        state.valueOrNull?.copyWith(historyFrequentCount: count) ??
            AppSettingsData(historyFrequentCount: count));
  }

  Future<void> setHistoryAllMealsCount(int count) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('history_all_meals_count', '$count');
    state = AsyncData(
        state.valueOrNull?.copyWith(historyAllMealsCount: count) ??
            AppSettingsData(historyAllMealsCount: count));
  }
}
