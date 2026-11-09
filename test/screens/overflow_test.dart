import 'dart:async';

import 'package:atharxa/data/finance_repo.dart';
import 'package:atharxa/data/food_repo.dart';
import 'package:atharxa/data/workout_repo.dart';
import 'package:atharxa/data/models.dart';
import 'package:atharxa/state/sync_controller.dart';
import 'package:atharxa/sync/discovery.dart';
import 'package:atharxa/sync/peers.dart';
import 'package:atharxa/ui/screens/finance/finance_screen.dart';
import 'package:atharxa/ui/screens/finance/transaction_sheet.dart';
import 'package:atharxa/ui/screens/workout/plan_editor_screen.dart';
import 'package:atharxa/ui/screens/workout/workout_screen.dart';
import 'package:atharxa/ui/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../finance_test.dart' show seedNovember;
import '../nutrition_test.dart' as sample;
import '../workout_test.dart' show seedLowerBodyA;
import 'render_helpers.dart';

/// Opens every screen and dialog at phone widths × text sizes. Any RenderFlex
/// overflow ("A RenderFlex overflowed by N pixels") fails the test, naming the
/// screen and setting.
class _FakeSync extends SyncController {
  @override
  SyncState build() => SyncState(
    enabled: true,
    deviceName: 'Android phone with a long name',
    code: '482913',
    autoSync: true,
    intervalMin: 5,
    listening: true,
    address: '192.168.100.123',
    paired: [
      PairedPeer(
        id: 'mac',
        name: 'Harshal’s MacBook Air (15-inch, M4)',
        host: '192.168.100.142',
        port: 47811,
        lastSyncAt: DateTime.now(),
        lastSent: 1234,
        lastReceived: 56789,
      ),
    ],
    discovered: const {
      'tab': DiscoveredPeer(id: 'tab', name: 'Pixel Tablet in the living room', host: '192.168.100.157', port: 47811),
    },
    busy: true,
    progress: (received: 12345, total: 67890),
  );
}

Future<void> seed(TestApp t) async {
  final repo = FoodRepo(t.db);
  final today = DateTime.now();
  final day = dayKey(today), tomorrow = dayKey(today.add(const Duration(days: 1)));
  final longFood = FoodItem(
    name: 'Homemade masala oats with roasted vegetables and peanuts',
    brand: 'Grandma’s kitchen recipe',
    servingG: 250,
    per100g: const Nutrients(kcal: 1234.5, protein: 123.4, carbs: 456.7, fiber: 78.9, fat: 99.9),
  );
  for (final (m, f, g) in [
    (Meal.breakfast, sample.oats, 60.0),
    (Meal.breakfast, longFood, 1250.0),
    (Meal.lunch, sample.paneer, 150.0),
    (Meal.snacks, sample.chana, 40.0),
  ]) {
    final saved = await repo.cache(f);
    await repo.add(FoodRepo.logs, day: day, meal: m, food: saved, grams: g);
    await repo.add(FoodRepo.plans, day: tomorrow, meal: m, food: saved, grams: g);
  }
  for (final ml in [250, 500, 1250]) {
    await t.db.save('water_logs', {
      'day': day,
      'ml': ml,
      'logged_at': today.millisecondsSinceEpoch,
      'source': 'notification',
    });
  }
  await t.db.setPref('profile_name', 'Harshal Deshpande with a rather long display name');
  await seedNovember(t.db);
  await seedLowerBodyA(t.db);
  // A month with long names and a big amount in the current month too.
  await t.db.save('transactions', {
    'day': dayKey(today),
    'kind': 'expense',
    'amount_minor': 123456789,
    'currency': 'INR',
    'category': 'Entertainment',
    'note': 'Concert tickets and dinner with the whole family at the new place',
  });
}

void main() {
  setUpAll(loadFonts);

  const sizes = {'360dp': Size(360, 780), 'pixel10': Size(411, 923), 'fold600': Size(600, 900)};
  const scales = [1.0, 1.3, 1.5];

  for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
    for (final scale in scales) {
      final label = '$sizeName @ ${(scale * 100).round()}%';

      testWidgets('main tabs · $label', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);
        for (final tab in ['Meal plan', 'Water', 'Workout', 'Finance', 'Overview']) {
          await goTo(tester, tab);
          // Scroll through the page so every card gets built and laid out.
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isEmpty) continue; // placeholder tabs
          final scrollable = scrollables.first;
          for (var i = 0; i < 6; i++) {
            await tester.drag(scrollable, const Offset(0, -500), warnIfMissed: false);
            await step(tester);
          }
        }
      });

      testWidgets('picker, portion, food editor · $label', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);
        await tester.ensureVisible(find.byTooltip('Add food to Lunch'));
        await step(tester);
        await tester.tap(find.byTooltip('Add food to Lunch'));
        await step(tester);
        await step(tester);
        await tester.tap(find.textContaining('Homemade masala oats').first);
        await step(tester);
        await tester.tap(find.text('Cancel'));
        await step(tester);
        await tester.tap(find.text('New food'));
        await step(tester);
      });

      testWidgets('water edit dialog + overview sheet · $label', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);
        await tester.tap(find.text('Water').first);
        await step(tester);
        await tester.tap(find.text('1,250 ml').last);
        await step(tester);
      });

      testWidgets('You › Goals, Appearance, Reminders, Body stats · $label', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);
        for (final section in ['Goals', 'Appearance', 'Reminders', 'Body stats']) {
          if (find.byType(NavigationRail).evaluate().isNotEmpty) {
            await goTo(tester, 'You');
          } else {
            await tester.tap(find.descendant(of: find.byType(AppTopBar), matching: find.byType(CircleAvatar)));
            await step(tester);
          }
          await tester.tap(find.text(section).first);
          await step(tester);
          final scrollable = find.byType(Scrollable).last;
          for (var i = 0; i < 4; i++) {
            await tester.drag(scrollable, const Offset(0, -500), warnIfMissed: false);
            await step(tester);
          }
          while (find.byType(BackButton).evaluate().isNotEmpty) {
            await tester.pageBack();
            await step(tester);
          }
        }
      });

      testWidgets('finance sheets · $label', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);
        await goTo(tester, 'Finance');
        await step(tester);
        // Transaction sheet (via the row) and the export sheet.
        // Open the edit sheet for the long transaction (same call the row's tap makes).
        final tx = (await tester.runAsync(
          () => FinanceRepo(t.db).month(DateFormat('yyyy-MM').format(DateTime.now())),
        ))!.firstWhere((x) => (x.note ?? '').startsWith('Concert'));
        unawaited(showTransactionSheet(tester.element(find.byType(FinanceScreen)), existing: tx));
        await step(tester);
        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -600), warnIfMissed: false);
        await step(tester);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop(); // close the sheet
        await step(tester);
        if (find.text('Export').evaluate().isNotEmpty) {
          await tester.tap(find.text('Export'));
        } else if (find.byTooltip('Export').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Export'));
        } else {
          await tester.tap(find.byTooltip('More'));
          await step(tester);
          await tester.tap(find.text('Export transactions'));
        }
        await step(tester);
        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -600), warnIfMissed: false);
        await step(tester);
      });

      testWidgets('workout: plan editor, session, complete · $label', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);
        await goTo(tester, 'Workout');
        // Plan editor + exercise dialog.
        final plan = (await tester.runAsync(() => WorkoutRepo(t.db).plans()))!.single;
        unawaited(PlanEditorScreen.open(tester.element(find.byType(WorkoutScreen)), plan: plan));
        await step(tester);
        await tester.tap(find.text('Goblet squat'));
        await step(tester);
        await tester.tap(find.text('Cancel'));
        await step(tester);
        await tester.tap(find.byTooltip('Share plan'));
        await step(tester);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await step(tester);
        await tester.pageBack();
        await step(tester);
        await tester.scrollUntilVisible(find.byTooltip('Import plans'), 300, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byTooltip('Import plans'));
        await step(tester);
        await tester.tap(find.text('Cancel'));
        await step(tester);
        await tester.scrollUntilVisible(find.text('Start workout'), -300, scrollable: find.byType(Scrollable).first);
        // Live session with the rest timer, then the complete screen.
        await tester.tap(find.text('Start workout'));
        await step(tester);
        await step(tester);
        await tester.tap(find.text('Complete set'));
        await step(tester);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -600), warnIfMissed: false);
        await step(tester);
        await tester.tap(find.text('End workout'));
        await step(tester);
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -600), warnIfMissed: false);
        await step(tester);
      });

      testWidgets('You hub + device sync · $label', (tester) async {
        setSize(tester, size);
        final t = (await tester.runAsync(
          () => buildTestApp(
            prefs: {'text_scale': scale},
            overrides: [syncControllerProvider.overrideWith(_FakeSync.new)],
          ),
        ))!;
        await tester.runAsync(() => seed(t));
        await tester.pumpWidget(t.app);
        await settle(tester);
        if (find.byType(NavigationRail).evaluate().isNotEmpty) {
          await goTo(tester, 'You');
        } else {
          await tester.tap(find.descendant(of: find.byType(AppTopBar), matching: find.byType(CircleAvatar)));
          await step(tester);
        }
        if (find.text('Paired devices').evaluate().isEmpty) {
          // Single-pane hub: open the page.
          await tester.tap(find.text('Device sync').first);
          await step(tester);
        }
        final scrollable = find.byType(Scrollable).last;
        for (var i = 0; i < 6; i++) {
          await tester.drag(scrollable, const Offset(0, -500), warnIfMissed: false);
          await step(tester);
        }
      });
    }
  }
}
