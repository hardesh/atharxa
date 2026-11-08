import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/food_repo.dart';
import '../data/models.dart';
import '../data/water_repo.dart';
import 'core_providers.dart';

/// Food log entries + water total for a day (Overview).
final overviewProvider = FutureProvider.family<({List<FoodEntry> entries, int waterMl}), String>((ref, day) async {
  ref.watchTables(const [FoodRepo.logs, WaterRepo.table]);
  final db = ref.watch(dbProvider);
  return (entries: await FoodRepo(db).entries(FoodRepo.logs, day), waterMl: await WaterRepo(db).total(day));
});

/// Planned items + what's already logged that day (Meal plan).
final mealPlanProvider = FutureProvider.family<({List<FoodEntry> plan, List<FoodEntry> logged}), String>((
  ref,
  day,
) async {
  ref.watchTables(const [FoodRepo.plans, FoodRepo.logs]);
  final repo = FoodRepo(ref.watch(dbProvider));
  return (plan: await repo.entries(FoodRepo.plans, day), logged: await repo.entries(FoodRepo.logs, day));
});

/// A day's water entries, newest first.
final waterEntriesProvider = FutureProvider.family<List<Map<String, Object?>>, String>((ref, day) {
  ref.watchTables(const [WaterRepo.table]);
  return WaterRepo(ref.watch(dbProvider)).entries(day);
});

/// ml per day for the 7 days ending on [day] (day key → ml).
final waterWeekProvider = FutureProvider.family<Map<String, int>, String>((ref, day) async {
  ref.watchTables(const [WaterRepo.table]);
  final db = ref.watch(dbProvider);
  final from = dayKey(parseDay(day).subtract(const Duration(days: 6)));
  final rows = await db.raw(
    'SELECT day, SUM(ml) AS ml FROM water_logs WHERE deleted = 0 AND day BETWEEN ? AND ? GROUP BY day',
    [from, day],
  );
  return {for (final r in rows) r['day'] as String: (r['ml'] as num).toInt()};
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
