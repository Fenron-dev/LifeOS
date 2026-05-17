import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../services/notification_service.dart';
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
  /// When true, constrained text (buttons, chips, cards) scales down instead of clipping.
  final bool autoSizeText;
  /// Maximum number of font-size steps (2pt each) allowed for auto-sizing (1–3).
  final int maxSizeReduction;
  /// Whether water reminder notifications are enabled.
  final bool waterReminderEnabled;
  /// Hour of day when water reminders start (0–23).
  final int waterReminderFromHour;
  /// Hour of day when water reminders end (0–23).
  final int waterReminderToHour;
  /// Interval between water reminders in minutes.
  final int waterReminderIntervalMinutes;

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
    this.autoSizeText = false,
    this.maxSizeReduction = 2,
    this.waterReminderEnabled = false,
    this.waterReminderFromHour = 8,
    this.waterReminderToHour = 22,
    this.waterReminderIntervalMinutes = 120,
  });

  AppSettingsData copyWith({
    ThemeMode? themeMode,
    Locale? locale,
    List<QuickAction>? quickActions,
    int? historyRecentCount,
    int? historyFrequentCount,
    int? historyAllMealsCount,
    bool? autoSizeText,
    int? maxSizeReduction,
    bool? waterReminderEnabled,
    int? waterReminderFromHour,
    int? waterReminderToHour,
    int? waterReminderIntervalMinutes,
  }) =>
      AppSettingsData(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        quickActions: quickActions ?? this.quickActions,
        historyRecentCount: historyRecentCount ?? this.historyRecentCount,
        historyFrequentCount: historyFrequentCount ?? this.historyFrequentCount,
        historyAllMealsCount: historyAllMealsCount ?? this.historyAllMealsCount,
        autoSizeText: autoSizeText ?? this.autoSizeText,
        maxSizeReduction: maxSizeReduction ?? this.maxSizeReduction,
        waterReminderEnabled: waterReminderEnabled ?? this.waterReminderEnabled,
        waterReminderFromHour:
            waterReminderFromHour ?? this.waterReminderFromHour,
        waterReminderToHour: waterReminderToHour ?? this.waterReminderToHour,
        waterReminderIntervalMinutes:
            waterReminderIntervalMinutes ?? this.waterReminderIntervalMinutes,
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
    final autoSizeText =
        (await db.getSetting('auto_size_text') ?? 'false') == 'true';
    final maxSizeReduction =
        int.tryParse(await db.getSetting('max_size_reduction') ?? '') ?? 2;
    final waterReminderEnabled =
        (await db.getSetting('water_reminder_enabled') ?? 'false') == 'true';
    final waterReminderFromHour =
        int.tryParse(await db.getSetting('water_reminder_from_hour') ?? '') ??
            8;
    final waterReminderToHour =
        int.tryParse(await db.getSetting('water_reminder_to_hour') ?? '') ?? 22;
    final waterReminderIntervalMinutes = int.tryParse(
            await db.getSetting('water_reminder_interval_minutes') ?? '') ??
        120;

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
      autoSizeText: autoSizeText,
      maxSizeReduction: maxSizeReduction,
      waterReminderEnabled: waterReminderEnabled,
      waterReminderFromHour: waterReminderFromHour,
      waterReminderToHour: waterReminderToHour,
      waterReminderIntervalMinutes: waterReminderIntervalMinutes,
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

  Future<void> setAutoSizeText(bool enabled) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('auto_size_text', enabled ? 'true' : 'false');
    state = AsyncData(state.valueOrNull?.copyWith(autoSizeText: enabled) ??
        AppSettingsData(autoSizeText: enabled));
  }

  Future<void> setMaxSizeReduction(int steps) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('max_size_reduction', '$steps');
    state = AsyncData(state.valueOrNull?.copyWith(maxSizeReduction: steps) ??
        AppSettingsData(maxSizeReduction: steps));
  }

  Future<void> setWaterReminderEnabled(bool enabled) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('water_reminder_enabled', enabled ? 'true' : 'false');
    final current = state.valueOrNull ?? const AppSettingsData();
    state = AsyncData(current.copyWith(waterReminderEnabled: enabled));
    if (enabled) {
      await NotificationService.scheduleWaterReminders(
        fromHour: current.waterReminderFromHour,
        toHour: current.waterReminderToHour,
        intervalMinutes: current.waterReminderIntervalMinutes,
      );
    } else {
      await NotificationService.cancelWaterReminders();
    }
  }

  Future<void> setWaterReminderFromHour(int hour) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('water_reminder_from_hour', '$hour');
    final current = state.valueOrNull ?? const AppSettingsData();
    state = AsyncData(current.copyWith(waterReminderFromHour: hour));
    if (current.waterReminderEnabled) {
      await NotificationService.scheduleWaterReminders(
        fromHour: hour,
        toHour: current.waterReminderToHour,
        intervalMinutes: current.waterReminderIntervalMinutes,
      );
    }
  }

  Future<void> setWaterReminderToHour(int hour) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('water_reminder_to_hour', '$hour');
    final current = state.valueOrNull ?? const AppSettingsData();
    state = AsyncData(current.copyWith(waterReminderToHour: hour));
    if (current.waterReminderEnabled) {
      await NotificationService.scheduleWaterReminders(
        fromHour: current.waterReminderFromHour,
        toHour: hour,
        intervalMinutes: current.waterReminderIntervalMinutes,
      );
    }
  }

  Future<void> setWaterReminderIntervalMinutes(int minutes) async {
    final db = ref.read(databaseProvider);
    if (db == null) return;
    await db.setSetting('water_reminder_interval_minutes', '$minutes');
    final current = state.valueOrNull ?? const AppSettingsData();
    state = AsyncData(current.copyWith(waterReminderIntervalMinutes: minutes));
    if (current.waterReminderEnabled) {
      await NotificationService.scheduleWaterReminders(
        fromHour: current.waterReminderFromHour,
        toHour: current.waterReminderToHour,
        intervalMinutes: minutes,
      );
    }
  }
}
