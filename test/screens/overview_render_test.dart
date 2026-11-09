import 'package:atharxa/app_clock.dart';
import 'package:atharxa/data/food_repo.dart';
import 'package:atharxa/data/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../nutrition_test.dart' as sample;
import 'render_helpers.dart';

/// Renders Today with the DESIGN.md §8 sample day. Run with
/// `flutter test --update-goldens test/screens` to refresh the PNGs in
/// test/screens/goldens/ for visual comparison with docs/design/boards.
void main() {
  setUpAll(loadFonts);

  Future<void> seed(TestApp t) async {
    final repo = FoodRepo(t.db);
    final day = dayKey(AppClock.now());
    Future<void> add(Meal m, FoodItem f, double g) async =>
        repo.add(FoodRepo.logs, day: day, meal: m, food: await repo.cache(f), grams: g);
    await add(Meal.breakfast, sample.oats, 60);
    await add(Meal.breakfast, sample.milk, 200);
    await add(Meal.breakfast, sample.banana, 120);
    await add(Meal.lunch, sample.paneer, 150);
    await add(Meal.lunch, sample.roti, 80);
    await add(Meal.lunch, sample.dal, 200);
    await add(Meal.snacks, sample.chana, 40);
    await add(Meal.snacks, sample.chai, 150);
    for (final ml in [500, 500, 250]) {
      await t.db.save('water_logs', {'day': day, 'ml': ml, 'logged_at': 0, 'source': 'today'});
    }
  }

  for (final (name, size, scale) in [
    ('overview_phone', const Size(412, 915), 1.3),
    ('overview_mac', const Size(1200, 860), 1.0),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('$name ${dark ? 'dark' : 'light'}', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(
          () => buildTestApp(prefs: {'text_scale': scale, 'theme_mode': dark ? 'dark' : 'light'}),
        ))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);

        expect(find.text('702'), findsOneWidget);
        expect(find.text('kcal left'), findsOneWidget);
        expect(find.text('Dinner'), findsOneWidget);
        expect(find.text('Nothing logged yet'), findsOneWidget);
        expect(find.text('1,250 / 3,000 ml'), findsOneWidget);

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${dark ? 'dark' : 'light'}.png'),
        );
      });
    }
  }

  testWidgets('food picker + portion dialog (phone)', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': 1.3})))!;
    await tester.runAsync(() => seed(t));
    await tester.pumpWidget(t.app);
    await settle(tester);

    await tester.ensureVisible(find.byTooltip('Add food to Lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add food to Lunch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add to Lunch', findRichText: true), findsOneWidget);
    expect(find.text('Rolled oats'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/picker_phone.png'));

    await tester.tap(find.text('Dal tadka'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Add to Lunch'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/portion_phone.png'));

    await tester.tap(find.widgetWithText(FilledButton, 'Add to Lunch'));
    await tester.pump();
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(find.text('Dal tadka · 100 g'), findsOneWidget);
  });
}
