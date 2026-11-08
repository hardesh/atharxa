import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../ui/theme/palettes.dart';

/// App-wide settings.
///
/// * **Synced** (stored in the `prefs` table, travels with Wi-Fi sync):
///   goals, theme palette, default currency, profile name.
/// * **Per device** (SharedPreferences, never synced): light/dark mode,
///   text size, first-run flag. Reminders, sync config and AI models keep
///   their own per-device stores.
class AppSettings extends ChangeNotifier {
  AppSettings._(this.db, this.prefs);

  final AppDb db;
  final SharedPreferences prefs;
  StreamSubscription<String>? _sub;

  AppPalette palette = AppPalette.forest;
  Goals goals = const Goals();
  String currency = 'INR';
  String profileName = '';

  static Future<AppSettings> load(AppDb db, SharedPreferences prefs) async {
    final s = AppSettings._(db, prefs);
    await s._loadSynced();
    s._sub = db.changes.where((t) => t == 'prefs').listen((_) async {
      await s._loadSynced();
      s.notifyListeners();
    });
    return s;
  }

  Future<void> _loadSynced() async {
    palette = AppPalette.parse(await db.getPref('theme'));
    currency = await db.getPref('currency_default') ?? 'INR';
    profileName = await db.getPref('profile_name') ?? '';
    double d(String? v, double def) => double.tryParse(v ?? '') ?? def;
    const g = Goals();
    goals = Goals(
      kcal: d(await db.getPref('goal_kcal'), g.kcal),
      waterMl: d(await db.getPref('goal_water'), g.waterMl.toDouble()).round(),
      protein: d(await db.getPref('goal_protein'), g.protein),
      carbs: d(await db.getPref('goal_carbs'), g.carbs),
      fiber: d(await db.getPref('goal_fiber'), g.fiber),
      fat: d(await db.getPref('goal_fat'), g.fat),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------- synced setters

  Future<void> setPalette(AppPalette p) => db.setPref('theme', p.name);
  Future<void> setCurrency(String code) => db.setPref('currency_default', code);
  Future<void> setProfileName(String name) => db.setPref('profile_name', name.trim());

  Future<void> setGoals(Goals g) async {
    await db.setPref('goal_kcal', '${g.kcal}');
    await db.setPref('goal_water', '${g.waterMl}');
    await db.setPref('goal_protein', '${g.protein}');
    await db.setPref('goal_carbs', '${g.carbs}');
    await db.setPref('goal_fiber', '${g.fiber}');
    await db.setPref('goal_fat', '${g.fat}');
  }

  // ---------------------------------------------------------- per-device values

  ThemeMode get themeMode => switch (prefs.getString('theme_mode')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode m) async {
    await prefs.setString('theme_mode', m.name);
    notifyListeners();
  }

  static const textSizes = [1.0, 1.15, 1.3, 1.5];

  /// 130 % default on phones, 100 % on the Mac (DESIGN.md §2).
  double get textScale => prefs.getDouble('text_scale') ?? (Platform.isAndroid ? 1.3 : 1.0);

  Future<void> setTextScale(double v) async {
    await prefs.setDouble('text_scale', v);
    notifyListeners();
  }

  bool get firstRunDone => prefs.getBool('first_run_done') ?? false;

  Future<void> setFirstRunDone() async {
    await prefs.setBool('first_run_done', true);
    notifyListeners();
  }

  String get initial {
    final n = profileName.trim();
    return n.isEmpty ? 'A' : n.characters.first.toUpperCase();
  }
}
