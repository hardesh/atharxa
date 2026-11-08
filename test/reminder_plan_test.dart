import 'package:atharxa/data/models.dart';
import 'package:atharxa/services/reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const goals = Goals(); // 2,200 kcal, 3,000 ml
  final now = DateTime(2026, 11, 9, 12, 0); // noon

  ReminderSettings all() => const ReminderSettings(
    mealsOn: {Meal.breakfast: true, Meal.lunch: true, Meal.snacks: true, Meal.dinner: true},
    waterOn: true,
    checkinOn: true,
  );

  test('today: only future times, logged meals skipped, live numbers in the text', () {
    final plan = planReminders(
      all(),
      now: now,
      goals: goals,
      today: const DaySnapshot(loggedMeals: {Meal.lunch}, plannedMeals: {Meal.dinner}, kcal: 1498, waterMl: 1250),
      days: 1,
    );
    expect(plan.every((r) => r.at.isAfter(now)), isTrue);
    final meals = plan.where((r) => r.kind == ReminderKind.meal).toList();
    // Breakfast (08:30) is past, lunch is logged → snacks and dinner remain.
    expect(meals.map((r) => r.meal), [Meal.snacks, Meal.dinner]);
    expect(meals.first.body, '702 kcal still to eat today');
    expect(meals.last.mealPlanned, isTrue); // dinner is planned → "Log dinner"
    final water = plan.where((r) => r.kind == ReminderKind.water).toList();
    expect(water.first.body, '1,250 of 3,000 ml today');
    // Every 2 h from 08:00 to 22:00 → 12:00 is not after noon, so 14:00 … 22:00.
    expect(water.map((r) => r.at.hour), [14, 16, 18, 20, 22]);
    final checkin = plan.where((r) => r.kind == ReminderKind.checkin).map((r) => r.body).toSet();
    expect(checkin, {'702 kcal left'});
  });

  test('water stops once the goal is met; later days start fresh; ids unique', () {
    final plan = planReminders(all(), now: now, goals: goals, today: const DaySnapshot(waterMl: 3000));
    final todayWater = plan.where((r) => r.kind == ReminderKind.water && r.day == '2026-11-09');
    expect(todayWater, isEmpty);
    final tomorrow = plan.where((r) => r.day == '2026-11-10').toList();
    expect(tomorrow.where((r) => r.kind == ReminderKind.meal).length, 4);
    expect(tomorrow.firstWhere((r) => r.kind == ReminderKind.water).body, '0 of 3,000 ml today');
    expect(plan.map((r) => r.id).toSet().length, plan.length);
    expect(plan.map((r) => r.day).toSet().length, 7);
  });

  test('turning reminders off keeps their times; JSON round-trip', () {
    final s = all().copyWith(waterOn: false, waterEveryH: 3, checkinTimes: [600, 1260]);
    final back = ReminderSettings.fromJson(s.toJson());
    expect(back.waterOn, isFalse);
    expect(back.waterEveryH, 3);
    expect(back.checkinTimes, [600, 1260]);
    expect(back.mealTimes[Meal.lunch], 780);
    expect(
      planReminders(
        back.copyWith(mealsOn: {for (final m in Meal.values) m: false}, checkinOn: false),
        now: now,
        goals: goals,
        today: DaySnapshot.empty,
      ),
      isEmpty,
    );
  });
}
