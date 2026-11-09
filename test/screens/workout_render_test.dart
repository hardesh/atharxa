import 'package:atharxa/data/models.dart';
import 'package:atharxa/data/workout_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workout_test.dart' show seedLowerBodyA;
import 'render_helpers.dart';

void main() {
  setUpAll(loadFonts);

  for (final (name, size, scale) in [
    ('workout_phone', const Size(412, 915), 1.3),
    ('workout_mac', const Size(1200, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      setSize(tester, size);
      final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
      await tester.runAsync(() => seedLowerBodyA(t.db));
      await tester.pumpWidget(t.app);
      await settle(tester);
      await goTo(tester, 'Workout');
      expect(find.text('Lower body A'), findsWidgets);
      expect(find.text('Start workout'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

      await tester.tap(find.text('Start workout'));
      await step(tester);
      await step(tester);
      expect(find.text('Goblet squat'), findsOneWidget);
      expect(find.text('Set 1 of 3 · target 10 reps · 16 kg'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_session.png'));
    });
  }

  testWidgets('session: complete sets with rest, end, save with kcal added to Today', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': 1.0})))!;
    await tester.runAsync(() => seedLowerBodyA(t.db));
    await tester.pumpWidget(t.app);
    await settle(tester);
    await goTo(tester, 'Workout');
    await tester.tap(find.text('Start workout'));
    await step(tester);
    await step(tester);

    await tester.tap(find.text('Complete set'));
    await step(tester);
    expect(find.textContaining('Rest '), findsOneWidget); // auto rest timer (90 s)
    expect(find.text('Set 2 of 3 · target 10 reps · 16 kg'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.tap(find.byTooltip('More kg'));
    await tester.pump();
    expect(find.text('18.5'), findsOneWidget);
    await tester.tap(find.text('Complete set'));
    await step(tester);

    await tester.tap(find.text('End workout'));
    await step(tester);
    expect(find.text('Workout complete'), findsOneWidget);
    expect(find.text('2 / 18'), findsOneWidget);
    expect(find.text('345 kg'), findsOneWidget); // 10 × 16 + 10 × 18.5
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/workout_complete_phone.png'));
    await tester.tap(find.text('Good'));
    await tester.tap(find.byType(Switch).first); // Add kcal to Today
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Save workout'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Save workout'));
    await step(tester);

    final s = (await tester.runAsync(
      () => WorkoutRepo(t.db).sessionsBetween(dayKey(DateTime.now()), dayKey(DateTime.now())),
    ))!;
    expect(s.single.finished, isTrue);
    expect(s.single.addKcalToToday, isTrue);
    expect(find.textContaining('min · 2 sets · 345 kg'), findsOneWidget);
  });
}
