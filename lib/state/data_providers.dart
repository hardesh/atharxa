import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/finance_repo.dart';
import '../data/food_repo.dart';
import '../data/models.dart';
import '../data/water_repo.dart';
import '../data/workout_repo.dart';
import 'core_providers.dart';

/// Screen data providers auto-dispose: a day/month's data is dropped once no
/// screen shows it, so browsing history doesn't grow memory.

/// Food log entries + water total for a day (Overview).
/// [workoutKcal]: calories from that day's workouts the user chose to add to
/// the day's budget ("Add kcal to Today").
final overviewProvider = FutureProvider.autoDispose
    .family<({List<FoodEntry> entries, int waterMl, double workoutKcal}), String>((ref, day) async {
      ref.watchTables(const [FoodRepo.logs, WaterRepo.table, 'sessions']);
      final db = ref.watch(dbProvider);
      return (
        entries: await FoodRepo(db).entries(FoodRepo.logs, day),
        waterMl: await WaterRepo(db).total(day),
        workoutKcal: await WorkoutRepo(db).kcalAddedOn(day),
      );
    });

/// Planned items + what's already logged that day (Meal plan).
final mealPlanProvider = FutureProvider.autoDispose.family<({List<FoodEntry> plan, List<FoodEntry> logged}), String>((
  ref,
  day,
) async {
  ref.watchTables(const [FoodRepo.plans, FoodRepo.logs]);
  final repo = FoodRepo(ref.watch(dbProvider));
  return (plan: await repo.entries(FoodRepo.plans, day), logged: await repo.entries(FoodRepo.logs, day));
});

/// A day's water entries, newest first.
final waterEntriesProvider = FutureProvider.autoDispose.family<List<Map<String, Object?>>, String>((ref, day) {
  ref.watchTables(const [WaterRepo.table]);
  return WaterRepo(ref.watch(dbProvider)).entries(day);
});

/// ml per day for the 7 days ending on [day] (day key → ml).
final waterWeekProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((ref, day) async {
  ref.watchTables(const [WaterRepo.table]);
  final db = ref.watch(dbProvider);
  final from = dayKey(parseDay(day).subtract(const Duration(days: 6)));
  final rows = await db.raw(
    'SELECT day, SUM(ml) AS ml FROM water_logs WHERE deleted = 0 AND day BETWEEN ? AND ? GROUP BY day',
    [from, day],
  );
  return {for (final r in rows) r['day'] as String: (r['ml'] as num).toInt()};
});

/// Transactions of a month ("2026-11").
final financeMonthProvider = FutureProvider.autoDispose.family<List<Tx>, String>((ref, yyyyMm) {
  ref.watchTables(const [FinanceRepo.table]);
  return FinanceRepo(ref.watch(dbProvider)).month(yyyyMm);
});

/// Category names for income or expenses (defaults, then custom).
final categoriesProvider = FutureProvider.autoDispose.family<List<String>, TxKind>((ref, kind) {
  ref.watchTables(const ['categories']);
  return FinanceRepo(ref.watch(dbProvider)).categories(kind);
});

/// The month shown on Finance (shared with the shell's Add/Export actions).
final financeMonthSelectedProvider = NotifierProvider<FinanceMonth, DateTime>(FinanceMonth.new);

class FinanceMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }

  void select(DateTime m) => state = DateTime(m.year, m.month);
}

/// Plans, this week's sessions and Strava activities (Mon–Sun around [day]),
/// and today's unfinished session.
final workoutProvider = FutureProvider.autoDispose
    .family<
      ({List<WorkoutPlan> plans, List<WorkoutSession> week, WorkoutSession? active, List<StravaActivity> strava}),
      String
    >((ref, day) async {
      ref.watchTables([...WorkoutRepo.tables, 'strava_activities']);
      final repo = WorkoutRepo(ref.watch(dbProvider));
      final d = parseDay(day);
      final monday = d.subtract(Duration(days: d.weekday - 1));
      final week = await repo.sessionsBetween(dayKey(monday), dayKey(monday.add(const Duration(days: 6))));
      return (
        plans: await repo.plans(),
        week: week,
        active: week.where((s) => !s.finished && s.day == day).firstOrNull,
        strava: await repo.stravaBetween(dayKey(monday), dayKey(monday.add(const Duration(days: 6)))),
      );
    });

/// Live row counts for [tables] (Data and backup), keyed by the tables'
/// names joined with commas so the family key is a plain value.
final dataCountsProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((ref, tables) {
  final list = tables.split(',');
  ref.watchTables(list);
  return ref.watch(dbProvider).countLive(list);
});

/// Renders an [AsyncValue]: previous data stays on screen while reloading;
/// a spinner shows only on first load.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnReload: true,
    data: (d) => builder(context, d),
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => Center(child: Text('Something went wrong: $e')),
  );
}
