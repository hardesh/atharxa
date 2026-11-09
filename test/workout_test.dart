import 'dart:io';

import 'package:atharxa/app_clock.dart';
import 'package:atharxa/data/db.dart';
import 'package:atharxa/data/exercise_tips.dart';
import 'package:atharxa/data/models.dart';
import 'package:atharxa/data/workout_repo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Board sample: "Lower body A", 6 exercises, 18 sets, about 45 min.
Future<WorkoutPlan> seedLowerBodyA(AppDb db, {Set<int>? days}) async {
  final repo = WorkoutRepo(db);
  await repo.savePlan(
    name: 'Lower body A',
    days: days ?? {AppClock.now().weekday},
    exercises: [
      {'name': 'Goblet squat', 'sets': 3, 'reps': 10, 'kg': 16.0, 'rest_s': 90},
      {'name': 'Romanian deadlift', 'sets': 3, 'reps': 10, 'kg': 30.0, 'rest_s': 90},
      {'name': 'Walking lunge', 'sets': 3, 'reps': 12, 'kg': 8.0, 'rest_s': 60},
      {'name': 'Glute bridge', 'sets': 3, 'reps': 15, 'kg': 20.0, 'rest_s': 60},
      {'name': 'Calf raise', 'sets': 3, 'reps': 15, 'kg': null, 'rest_s': 45},
      {'name': 'Plank', 'sets': 3, 'reps': 45, 'kg': null, 'rest_s': 45},
    ],
  );
  return (await repo.plans()).single;
}

void main() {
  test('plans: order kept, summary text, estimate, removed exercises deleted', () async {
    final db = await openTestDb();
    final p = await seedLowerBodyA(db, days: {1, 3, 5});
    expect(p.exercises.map((e) => e.name).first, 'Goblet squat');
    expect(p.totalSets, 18);
    expect(p.exercises.first.summary, '3 × 10 · 16 kg · rest 90s');
    expect(p.exercises[4].summary, '3 × 15 · bodyweight · rest 45s');
    // 18 × 60 s work + rests between sets 2·(90+90+60+60+45+45) + 6 × 120 s changeover = 2,580 s → 43 min
    expect(p.estimatedMinutes, 43);
    expect(p.repeatsOn(DateTime(2026, 11, 9)), isTrue); // Monday
    expect(p.repeatsOn(DateTime(2026, 11, 10)), isFalse);

    final repo = WorkoutRepo(db);
    await repo.savePlan(
      id: p.id,
      name: 'Lower body A',
      days: p.days,
      exercises: [for (final e in p.exercises.reversed.take(2)) e.row],
    );
    final again = (await repo.plans()).single;
    expect(again.exercises.map((e) => e.name), ['Plank', 'Calf raise']);
  });

  test('session: sets, volume, kcal added to the day only when chosen', () async {
    final db = await openTestDb();
    final p = await seedLowerBodyA(db);
    final repo = WorkoutRepo(db);
    final id = await repo.startSession(p);
    await repo.logSet(id, p.exercises[0], setNo: 1, reps: 10, kg: 16);
    await repo.logSet(id, p.exercises[0], setNo: 2, reps: 8, kg: 18);
    await repo.logSet(id, p.exercises[5], setNo: 1, reps: 45);
    final s = (await repo.session(id))!;
    expect(s.sets.length, 3);
    expect(s.volume, 10 * 16 + 8 * 18.0);
    expect(s.finished, isFalse);
    final today = dayKey(AppClock.now());
    await repo.finishSession(s, feel: 'good', notes: ' ', kcal: 260, addKcalToToday: false);
    expect(await repo.kcalAddedOn(today), 0);
    await repo.finishSession((await repo.session(id))!, feel: 'good', notes: null, kcal: 260, addKcalToToday: true);
    expect(await repo.kcalAddedOn(today), 260);
  });

  test('energy estimate: MET 5 × weight × hours', () {
    expect(estimateKcal(duration: const Duration(minutes: 46), bodyWeightKg: 68), closeTo(260.7, 0.1));
    expect(estimateKcal(duration: const Duration(hours: 1)), 350); // 70 kg default
  });

  test('form tips match by exact name, then the longest key contained', () {
    final all = ExerciseTips.parseForTest(File('assets/data/exercise_tips.json').readAsStringSync());
    expect(ExerciseTips.match(all, 'Goblet squat')!.mistake, 'Knees caving in on the way up.');
    expect(ExerciseTips.match(all, 'Front squat')!.tips.first, 'Brace before each rep');
    expect(ExerciseTips.match(all, 'Walking lunge'), isNotNull);
    expect(ExerciseTips.match(all, 'Juggling'), isNull);
  });
}
