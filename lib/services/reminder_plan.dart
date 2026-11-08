import 'dart:convert';

import '../data/models.dart';
import '../ui/format.dart';

/// Minutes after midnight ("13:00" ↔ 780).
typedef ClockTime = int;

String fmtClock(ClockTime t) => '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';

/// Reminder settings (per device, never synced). DESIGN.md §5 You › Reminders.
/// Turning a reminder off keeps its times.
class ReminderSettings {
  const ReminderSettings({
    this.mealsOn = const {Meal.breakfast: false, Meal.lunch: false, Meal.snacks: false, Meal.dinner: false},
    this.mealTimes = const {Meal.breakfast: 510, Meal.lunch: 780, Meal.snacks: 990, Meal.dinner: 1230},
    this.waterOn = false,
    this.waterEveryH = 2,
    this.waterStart = 480,
    this.waterEnd = 1320,
    this.checkinOn = false,
    this.checkinTimes = const [660, 990, 1200],
  });

  final Map<Meal, bool> mealsOn;
  final Map<Meal, ClockTime> mealTimes;
  final bool waterOn, checkinOn;
  final int waterEveryH;
  final ClockTime waterStart, waterEnd;
  final List<ClockTime> checkinTimes;

  bool get anyOn => waterOn || checkinOn || mealsOn.values.any((v) => v);

  ReminderSettings copyWith({
    Map<Meal, bool>? mealsOn,
    Map<Meal, ClockTime>? mealTimes,
    bool? waterOn,
    int? waterEveryH,
    ClockTime? waterStart,
    ClockTime? waterEnd,
    bool? checkinOn,
    List<ClockTime>? checkinTimes,
  }) => ReminderSettings(
    mealsOn: mealsOn ?? this.mealsOn,
    mealTimes: mealTimes ?? this.mealTimes,
    waterOn: waterOn ?? this.waterOn,
    waterEveryH: waterEveryH ?? this.waterEveryH,
    waterStart: waterStart ?? this.waterStart,
    waterEnd: waterEnd ?? this.waterEnd,
    checkinOn: checkinOn ?? this.checkinOn,
    checkinTimes: checkinTimes ?? this.checkinTimes,
  );

  String toJson() => jsonEncode({
    'mealsOn': {for (final e in mealsOn.entries) e.key.name: e.value},
    'mealTimes': {for (final e in mealTimes.entries) e.key.name: e.value},
    'waterOn': waterOn,
    'waterEveryH': waterEveryH,
    'waterStart': waterStart,
    'waterEnd': waterEnd,
    'checkinOn': checkinOn,
    'checkinTimes': checkinTimes,
  });

  static ReminderSettings fromJson(String? s) {
    const d = ReminderSettings();
    if (s == null) return d;
    final j = jsonDecode(s) as Map<String, dynamic>;
    Map<Meal, T> meals<T>(Object? m, Map<Meal, T> def) => {
      for (final meal in Meal.values) meal: ((m as Map?)?[meal.name] as T?) ?? def[meal] as T,
    };
    return ReminderSettings(
      mealsOn: meals(j['mealsOn'], d.mealsOn),
      mealTimes: meals(j['mealTimes'], d.mealTimes),
      waterOn: j['waterOn'] as bool? ?? d.waterOn,
      waterEveryH: j['waterEveryH'] as int? ?? d.waterEveryH,
      waterStart: j['waterStart'] as int? ?? d.waterStart,
      waterEnd: j['waterEnd'] as int? ?? d.waterEnd,
      checkinOn: j['checkinOn'] as bool? ?? d.checkinOn,
      checkinTimes: [...(j['checkinTimes'] as List? ?? d.checkinTimes).cast<int>()]..sort(),
    );
  }
}

/// What has been logged on a day — the reminder text and skips depend on it.
class DaySnapshot {
  const DaySnapshot({
    this.loggedMeals = const {},
    this.plannedMeals = const {},
    this.kcal = 0,
    this.protein,
    this.waterMl = 0,
  });

  /// A fresh day (nothing logged yet) — used for days after today.
  static const empty = DaySnapshot();

  final Set<Meal> loggedMeals, plannedMeals;
  final double kcal;
  final double? protein;
  final int waterMl;
}

enum ReminderKind { meal, water, checkin }

/// One notification to schedule.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.body,
    this.meal,
    this.mealPlanned = false,
  });

  final int id;
  final DateTime at;
  final ReminderKind kind;
  final String title, body;
  final Meal? meal;

  /// The meal has planned items → offer "Log lunch" (logs the plan) instead
  /// of "Add lunch" (opens the app).
  final bool mealPlanned;

  String get day => dayKey(at);
}

/// Text helpers shared by scheduling and the notification action handler.
abstract final class ReminderText {
  static String waterBody(int ml, int goal) => '${fmtInt(ml)} of ${fmtInt(goal)} ml today';
  static String mealBody(double kcalLeft) =>
      kcalLeft > 0 ? '${fmtInt(kcalLeft)} kcal still to eat today' : 'Daily calorie goal reached';
  static String checkinBody(double kcal, double? protein, Goals g) {
    final left = g.kcal - kcal;
    final p = protein == null ? '' : ' · Protein ${fmtMacro(protein)} / ${fmtInt(g.protein)} g';
    return '${left >= 0 ? '${fmtInt(left)} kcal left' : '${fmtInt(-left)} kcal over'}$p';
  }
}

/// Reminders from [now] through the end of the day [days] days ahead.
///
/// Notifications are one-shot and recomputed whenever food or water changes,
/// so today's text shows live numbers and logged meals are skipped. Later days
/// assume a fresh day. Ids are stable per (day offset, slot) so rescheduling
/// replaces rather than duplicates.
List<PlannedReminder> planReminders(
  ReminderSettings s, {
  required DateTime now,
  required Goals goals,
  required DaySnapshot today,
  Map<String, Set<Meal>> plannedByDay = const {},
  int days = 7,
}) {
  final out = <PlannedReminder>[];
  final midnight = DateTime(now.year, now.month, now.day);
  for (var d = 0; d < days; d++) {
    final day = DateTime(midnight.year, midnight.month, midnight.day + d);
    final snap = d == 0 ? today : DaySnapshot.empty;
    final planned = plannedByDay[dayKey(day)] ?? (d == 0 ? today.plannedMeals : const <Meal>{});
    void add(int slot, ClockTime t, ReminderKind kind, String title, String body, {Meal? meal}) {
      final at = day.add(Duration(minutes: t));
      if (!at.isAfter(now)) return;
      out.add(
        PlannedReminder(
          id: 1000 + d * 100 + slot,
          at: at,
          kind: kind,
          title: title,
          body: body,
          meal: meal,
          mealPlanned: meal != null && planned.contains(meal),
        ),
      );
    }

    for (final (i, meal) in Meal.values.indexed) {
      if (s.mealsOn[meal] != true || snap.loggedMeals.contains(meal)) continue;
      add(
        i,
        s.mealTimes[meal]!,
        ReminderKind.meal,
        '${meal.label} time',
        ReminderText.mealBody(goals.kcal - snap.kcal),
        meal: meal,
      );
    }
    if (s.waterOn && snap.waterMl < goals.waterMl && s.waterEveryH > 0) {
      var slot = 10;
      for (var t = s.waterStart; t <= s.waterEnd && slot < 40; t += s.waterEveryH * 60) {
        add(
          slot++,
          t,
          ReminderKind.water,
          'Time for a glass of water',
          ReminderText.waterBody(snap.waterMl, goals.waterMl),
        );
      }
    }
    if (s.checkinOn) {
      for (final (i, t) in s.checkinTimes.take(10).indexed) {
        add(
          50 + i,
          t,
          ReminderKind.checkin,
          'Calorie check-in',
          ReminderText.checkinBody(snap.kcal, snap.protein, goals),
        );
      }
    }
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}
