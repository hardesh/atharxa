import 'package:atharxa/data/workout_repo.dart';
import 'package:atharxa/services/workout_share.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'workout_test.dart' show seedLowerBodyA;

void main() {
  test('share message round-trips into another device as a new plan', () async {
    final mine = await openTestDb(), parents = await openTestDb();
    final plan = await seedLowerBodyA(mine, days: {1, 3, 5});
    await WorkoutRepo(mine).savePlan(
      id: plan.id,
      name: plan.name,
      days: plan.days,
      exercises: [
        {...plan.exercises.first.row, 'videos': '["https://youtu.be/dQw4w9WgXcQ"]'},
        ...plan.exercises.skip(1).map((e) => e.row),
      ],
    );
    final shared = WorkoutShare.encodeMessage([(await WorkoutRepo(mine).plans()).single]);
    expect(shared, startsWith('Atharxa workout plan: Lower body A\n'));

    // Pasted with chat noise around it.
    final names = await WorkoutShare.import(
      parents,
      WorkoutShare.decode('Hi Mom! here it is:\n$shared\nsent from my phone'),
    );
    expect(names, ['Lower body A']);
    final got = (await WorkoutRepo(parents).plans()).single;
    expect(got.days, {1, 3, 5});
    expect(got.exercises.map((e) => e.summary), plan.exercises.map((e) => e.summary));
    expect(got.exercises.first.videos, ['https://youtu.be/dQw4w9WgXcQ']);
    expect(got.id, isNot(plan.id)); // a new plan, not a synced copy

    // Importing again keeps both.
    expect(await WorkoutShare.import(parents, WorkoutShare.decode(shared)), ['Lower body A (2)']);
  });

  test('file JSON decodes too; bad input gives a clear message', () async {
    final db = await openTestDb();
    final plan = await seedLowerBodyA(db);
    expect(WorkoutShare.decode(WorkoutShare.encodeJson([plan])).single.exercises.length, 6);
    expect(WorkoutShare.fileName([plan]), 'workout-plan-lower-body-a.json');
    expect(() => WorkoutShare.decode('hello'), throwsA(isA<FormatException>()));
    expect(() => WorkoutShare.decode('{"format":"other"}'), throwsA(isA<FormatException>()));
    expect(() => WorkoutShare.decode('{"format":"workout-plans","plans":[{"na'), throwsA(isA<FormatException>()));
  });
}
