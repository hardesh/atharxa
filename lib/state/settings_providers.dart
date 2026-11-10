import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../ui/theme/palettes.dart';
import 'core_providers.dart';
import '../app_clock.dart';

// ----------------------------------------------------------------- synced

/// Settings stored in the `prefs` table and carried by Wi-Fi sync:
/// goals, theme palette, default currency, profile name.
@immutable
class SyncedSettings {
  const SyncedSettings({
    this.palette = AppPalette.forest,
    this.goals = const Goals(),
    this.currency = 'INR',
    this.profileName = '',
    this.body = const BodyStats(),
  });

  final AppPalette palette;
  final Goals goals;
  final String currency;
  final String profileName;
  final BodyStats body;

  String get initial {
    final n = profileName.trim();
    return n.isEmpty ? 'A' : n.characters.first.toUpperCase();
  }

  static Future<SyncedSettings> load(AppDb db) async {
    double d(String? v, double def) => double.tryParse(v ?? '') ?? def;
    const g = Goals();
    return SyncedSettings(
      palette: AppPalette.parse(await db.getPref('theme')),
      currency: await db.getPref('currency_default') ?? 'INR',
      profileName: await db.getPref('profile_name') ?? '',
      body: BodyStats(
        heightCm: double.tryParse(await db.getPref('body_height') ?? ''),
        weightKg: double.tryParse(await db.getPref('body_weight') ?? ''),
        birthYear: int.tryParse(await db.getPref('body_birth_year') ?? ''),
        sex: switch (await db.getPref('body_sex')) {
          'male' => Sex.male,
          'female' => Sex.female,
          _ => null,
        },
        activity: ActivityLevel.parse(await db.getPref('body_activity')),
      ),
      goals: Goals(
        kcal: d(await db.getPref('goal_kcal'), g.kcal),
        waterMl: d(await db.getPref('goal_water'), g.waterMl.toDouble()).round(),
        protein: d(await db.getPref('goal_protein'), g.protein),
        carbs: d(await db.getPref('goal_carbs'), g.carbs),
        fiber: d(await db.getPref('goal_fiber'), g.fiber),
        fat: d(await db.getPref('goal_fat'), g.fat),
      ),
    );
  }
}

/// Loaded before `runApp` (so the first frame has the right theme) and
/// injected with `overrideWithValue`.
final initialSyncedSettingsProvider = Provider<SyncedSettings>((ref) => const SyncedSettings());

final syncedSettingsProvider = NotifierProvider<SyncedSettingsNotifier, SyncedSettings>(SyncedSettingsNotifier.new);

class SyncedSettingsNotifier extends Notifier<SyncedSettings> {
  AppDb get _db => ref.read(dbProvider);

  @override
  SyncedSettings build() {
    final db = ref.watch(dbProvider);
    // Reload when prefs change locally or arrive from the other device.
    final sub = db.changes.where((t) => t == 'prefs').listen((_) async {
      final s = await SyncedSettings.load(db);
      if (ref.mounted) state = s;
    });
    ref.onDispose(sub.cancel);
    return ref.read(initialSyncedSettingsProvider);
  }

  Future<void> setPalette(AppPalette p) => _db.setPref('theme', p.name);
  Future<void> setCurrency(String code) => _db.setPref('currency_default', code);
  Future<void> setProfileName(String name) => _db.setPref('profile_name', name.trim());

  Future<void> setBodyStats(BodyStats b) async {
    Future<void> put(String key, Object? v) => _db.setPref(key, v == null ? '' : '$v');
    await put('body_height', b.heightCm);
    await put('body_weight', b.weightKg);
    await put('body_birth_year', b.birthYear);
    await put('body_sex', b.sex?.name);
    await put('body_activity', b.activity.name);
  }

  Future<void> setGoals(Goals g) async {
    await _db.setPref('goal_kcal', '${g.kcal}');
    await _db.setPref('goal_water', '${g.waterMl}');
    await _db.setPref('goal_protein', '${g.protein}');
    await _db.setPref('goal_carbs', '${g.carbs}');
    await _db.setPref('goal_fiber', '${g.fiber}');
    await _db.setPref('goal_fat', '${g.fat}');
  }
}

/// Shorthand for the synced goals.
final goalsProvider = Provider<Goals>((ref) => ref.watch(syncedSettingsProvider.select((s) => s.goals)));

// ------------------------------------------------------------- per device

/// Settings that never sync: light/dark mode, text size, first-run flag,
/// when this device last made a backup.
@immutable
class DeviceSettings {
  const DeviceSettings({
    required this.themeMode,
    required this.textScale,
    required this.firstRunDone,
    this.lastBackupAt,
  });

  final ThemeMode themeMode;
  final double textScale;
  final bool firstRunDone;
  final DateTime? lastBackupAt;

  static const textSizes = [1.0, 1.15, 1.3, 1.5];
}

final deviceSettingsProvider = NotifierProvider<DeviceSettingsNotifier, DeviceSettings>(DeviceSettingsNotifier.new);

class DeviceSettingsNotifier extends Notifier<DeviceSettings> {
  @override
  DeviceSettings build() {
    final p = ref.watch(prefsProvider);
    return DeviceSettings(
      themeMode: switch (p.getString(DeviceKeys.themeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      // 130 % default on phones, 100 % on the Mac (DESIGN.md §2).
      textScale: p.getDouble(DeviceKeys.textScale) ?? (Platform.isAndroid ? 1.3 : 1.0),
      firstRunDone: p.getBool(DeviceKeys.firstRunDone) ?? false,
      lastBackupAt: DateTime.tryParse(p.getString(DeviceKeys.lastBackupAt) ?? ''),
    );
  }

  Future<void> setThemeMode(ThemeMode m) async {
    await ref.read(prefsProvider).setString(DeviceKeys.themeMode, m.name);
    ref.invalidateSelf();
  }

  Future<void> setTextScale(double v) async {
    await ref.read(prefsProvider).setDouble(DeviceKeys.textScale, v);
    ref.invalidateSelf();
  }

  Future<void> setBackedUp(DateTime at) async {
    await ref.read(prefsProvider).setString(DeviceKeys.lastBackupAt, at.toIso8601String());
    ref.invalidateSelf();
  }

  Future<void> setFirstRunDone() async {
    await ref.read(prefsProvider).setBool(DeviceKeys.firstRunDone, true);
    ref.invalidateSelf();
  }
}

// ----------------------------------------------------------- selected day

/// The day shown on Overview and Water (shared, so a quick-add on one always
/// lands on the day the other shows). While on "today" it follows the
/// calendar: it rolls over when the app is resumed on a later day.
final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(SelectedDayNotifier.new);

class SelectedDayNotifier extends Notifier<DateTime> {
  bool _followToday = true;

  static DateTime today() {
    final n = AppClock.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  DateTime build() {
    final listener = AppLifecycleListener(onResume: refresh);
    ref.onDispose(listener.dispose);
    return today();
  }

  void select(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    _followToday = day == today();
    state = day;
  }

  /// Re-checks the calendar (app resume, or before a quick-add).
  void refresh() {
    if (_followToday && state != today()) state = today();
  }
}

/// Whether the selected day's food and water can be changed: today yes;
/// past days are locked until unlocked; future days never (that is what
/// Meal plan is for).
enum DayAccess {
  today,
  lockedPast,
  unlockedPast,
  future;

  bool get canEdit => this == today || this == unlockedPast;
}

/// The past day the user unlocked for editing (in memory: it locks again
/// when the app restarts).
final unlockedDayProvider = NotifierProvider<UnlockedDay, String?>(UnlockedDay.new);

class UnlockedDay extends Notifier<String?> {
  @override
  String? build() => null;
  void unlock(String day) => state = day;
  void lock() => state = null;
}

final dayAccessProvider = Provider<DayAccess>((ref) {
  final day = dayKey(ref.watch(selectedDayProvider));
  final today = dayKey(SelectedDayNotifier.today());
  if (day == today) return DayAccess.today;
  if (day.compareTo(today) > 0) return DayAccess.future;
  return ref.watch(unlockedDayProvider) == day ? DayAccess.unlockedPast : DayAccess.lockedPast;
});
