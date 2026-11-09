import 'package:atharxa/app_clock.dart';
import 'package:atharxa/data/food_repo.dart';
import 'package:atharxa/data/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nutrition_test.dart' as sample;
import 'render_helpers.dart';

void main() {
  setUpAll(loadFonts);

  final tomorrow = dayKey(AppClock.now().add(const Duration(days: 1)));

  Future<void> seed(TestApp t) async {
    final repo = FoodRepo(t.db);
    Future<void> add(Meal m, FoodItem f, double g) async =>
        repo.add(FoodRepo.plans, day: tomorrow, meal: m, food: await repo.cache(f), grams: g);
    await add(Meal.breakfast, sample.oats, 80);
    await add(Meal.breakfast, sample.milk, 250);
    await add(Meal.lunch, sample.roti, 120);
    await add(Meal.lunch, sample.dal, 250);
    await add(Meal.lunch, sample.paneer, 150);
    await add(Meal.snacks, sample.banana, 120);
    await add(Meal.snacks, sample.chana, 40);
  }

  Future<void> openMealPlan(WidgetTester tester) async {
    await goTo(tester, 'Meal plan');
  }

  for (final (name, size, scale) in [
    ('plan_phone', const Size(412, 915), 1.3),
    ('plan_mac', const Size(1200, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      setSize(tester, size);
      final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
      await tester.runAsync(() => seed(t));
      await tester.pumpWidget(t.app);
      await settle(tester);
      await openMealPlan(tester);
      expect(find.textContaining('Tomorrow'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    });
  }

  testWidgets('Log whole day copies the plan; logging twice asks first', (tester) async {
    setSize(tester, const Size(1200, 860));
    final t = (await tester.runAsync(() => buildTestApp()))!;
    await tester.runAsync(() => seed(t));
    await tester.pumpWidget(t.app);
    await settle(tester);
    await openMealPlan(tester);

    Future<void> logDay() async {
      await tester.tap(find.byTooltip('Plan options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log whole day'));
      await tester.pump();
      await settle(tester);
    }

    await logDay();
    final logged = (await tester.runAsync(() => FoodRepo(t.db).entries(FoodRepo.logs, tomorrow)))!;
    expect(logged.length, 7);

    await logDay();
    expect(find.text('Log the whole day again?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await settle(tester);
    final again = (await tester.runAsync(() => FoodRepo(t.db).entries(FoodRepo.logs, tomorrow)))!;
    expect(again.length, 7);
  });
}
