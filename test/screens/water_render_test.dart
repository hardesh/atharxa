import 'package:atharxa/app_clock.dart';
import 'package:atharxa/data/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_helpers.dart';

void main() {
  setUpAll(loadFonts);

  Future<void> seed(TestApp t) async {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final past = [3100, 2400, 3000, 1800, 3200, 3050];
    for (var i = 0; i < past.length; i++) {
      final d = today.subtract(Duration(days: 6 - i));
      await t.db.save('water_logs', {
        'day': dayKey(d),
        'ml': past[i],
        'logged_at': d.millisecondsSinceEpoch,
        'source': 'water',
      });
    }
    for (final (h, m, ml, src) in [
      (7, 40, 250, 'today'),
      (9, 15, 500, 'water'),
      (11, 30, 250, 'today'),
      (13, 5, 250, 'notification'),
    ]) {
      await t.db.save('water_logs', {
        'day': dayKey(today),
        'ml': ml,
        'logged_at': today.add(Duration(hours: h, minutes: m)).millisecondsSinceEpoch,
        'source': src,
      });
    }
  }

  for (final (name, size, scale) in [
    ('water_phone', const Size(412, 915), 1.3),
    ('water_mac', const Size(1200, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      setSize(tester, size);
      final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': scale})))!;
      await tester.runAsync(() => seed(t));
      await tester.pumpWidget(t.app);
      await settle(tester);
      await goTo(tester, 'Water');
      expect(find.text('1,250'), findsWidgets);
      expect(find.text('1,750 to go'), findsOneWidget);
      expect(find.textContaining('Goal met 4 of 7'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

      await tester.tap(find.text('+500 ml'));
      await tester.pump();
      await settle(tester);
      expect(find.text('1,750'), findsWidgets);
    });
  }

  testWidgets('Today and Water share the selected day', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp()))!;
    await tester.pumpWidget(t.app);
    await settle(tester);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pump();
    await settle(tester);
    expect(find.textContaining('Yesterday'), findsOneWidget);
    // Past days are locked until unlocked.
    await tester.tap(find.text('Unlock to edit'));
    await tester.pump();
    await tester.tap(find.text('500 ml'));
    await tester.pump();
    await settle(tester);

    await goTo(tester, 'Water');
    expect(find.textContaining('Yesterday'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
  });

  testWidgets('water: undo an add, edit an entry, delete from the edit dialog', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp()))!;
    await tester.pumpWidget(t.app);
    await settle(tester);

    // Mistaken tap on Today → Undo.
    await tester.tap(find.text('500 ml'));
    await tester.pump();
    await settle(tester);
    expect(find.text('500 / 3,000 ml'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await settle(tester);
    expect(find.text('0 / 3,000 ml'), findsOneWidget);

    // Add 250, then open the entries sheet from the Overview card and edit to 300.
    await tester.tap(find.text('250 ml'));
    await tester.pump();
    await settle(tester);
    await tester.tap(find.text('Water').first);
    await step(tester);
    await settle(tester);
    expect(find.text('Tap an entry to change it.'), findsOneWidget);
    await tester.tap(find.text('250 ml').last);
    await step(tester);
    expect(find.text('Edit water'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '300');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await settle(tester);
    await step(tester);
    expect(find.text('300 ml'), findsOneWidget);

    // Delete it from the edit dialog.
    await tester.tap(find.text('300 ml'));
    await step(tester);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await settle(tester);
    await step(tester);
    expect(find.text('No water logged yet'), findsOneWidget);
  });
}
