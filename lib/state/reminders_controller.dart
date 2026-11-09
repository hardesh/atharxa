import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/food_repo.dart';
import '../data/models.dart';
import '../data/water_repo.dart';
import '../services/reminder_plan.dart';
import 'core_providers.dart';
import 'settings_providers.dart';
import '../app_clock.dart';

/// Reminder settings (per device) + keeping the scheduled notifications in
/// step with what has been logged. Started once from `main`.
final remindersProvider = NotifierProvider<RemindersController, ReminderSettings>(RemindersController.new);

/// A meal the user asked to add from a notification ("Add lunch" / tap);
/// the shell opens the food picker and clears it.
final pendingMealProvider = NotifierProvider<PendingMeal, Meal?>(PendingMeal.new);

class PendingMeal extends Notifier<Meal?> {
  @override
  Meal? build() => null;
  void request(Meal? m) => state = m;
}

class RemindersController extends Notifier<ReminderSettings> {
  Timer? _debounce;

  @override
  ReminderSettings build() {
    final db = ref.watch(dbProvider);
    // Logged food/water, plans and goals change the text and the skips.
    final sub = db.changes
        .where((t) => const {FoodRepo.logs, FoodRepo.plans, WaterRepo.table, 'prefs'}.contains(t))
        .listen((_) => _scheduleSoon());
    final life = AppLifecycleListener(
      onResume: () {
        // Notification actions may have written while the app was in the background.
        db.notifyExternalChange();
        _scheduleSoon();
      },
    );
    ref.onDispose(() {
      sub.cancel();
      life.dispose();
      _debounce?.cancel();
    });
    _scheduleSoon();
    return ReminderSettings.fromJson(ref.watch(prefsProvider).getString(DeviceKeys.reminders));
  }

  Future<void> update(ReminderSettings s) async {
    final turnedOn = s.anyOn && !state.anyOn;
    await ref.read(prefsProvider).setString(DeviceKeys.reminders, s.toJson());
    state = s;
    if (turnedOn) await ref.read(notificationServiceProvider).requestPermission();
    await reschedule();
  }

  Future<void> sendTest() => ref.read(notificationServiceProvider).showTest();

  void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), reschedule);
  }

  /// Recomputes and replaces all scheduled reminders.
  Future<void> reschedule() async {
    final service = ref.read(notificationServiceProvider);
    if (!service.ready) return;
    final s = state;
    if (!s.anyOn) return service.schedule(const []);
    final db = ref.read(dbProvider);
    final now = AppClock.now();
    final today = dayKey(now);
    final food = FoodRepo(db);
    final logs = await food.entries(FoodRepo.logs, today);
    final totals = Nutrients.sum(logs.map((e) => e.totals));
    final plans = await db.raw('SELECT DISTINCT day, meal FROM meal_plans WHERE deleted = 0 AND day BETWEEN ? AND ?', [
      today,
      dayKey(now.add(const Duration(days: 6))),
    ]);
    final plannedByDay = <String, Set<Meal>>{};
    for (final r in plans) {
      (plannedByDay[r['day'] as String] ??= {}).add(Meal.parse(r['meal'] as String));
    }
    final plan = planReminders(
      s,
      now: now,
      goals: (await SyncedSettings.load(db)).goals,
      today: DaySnapshot(
        loggedMeals: logs.map((e) => e.meal).toSet(),
        kcal: totals.kcal,
        protein: totals.protein,
        waterMl: await WaterRepo(db).total(today),
      ),
      plannedByDay: plannedByDay,
    );
    if (ref.mounted) await service.schedule(plan);
  }
}
