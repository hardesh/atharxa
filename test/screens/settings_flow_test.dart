import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atharxa/app_clock.dart';
import 'package:atharxa/ui/widgets/top_bar.dart';

import 'render_helpers.dart';

Future<void> openSection(WidgetTester tester, String section) async {
  await tester.tap(find.descendant(of: find.byType(AppTopBar), matching: find.byType(CircleAvatar)));
  await step(tester);
  await tester.tap(find.text(section));
  await step(tester);
}

void main() {
  setUpAll(loadFonts);

  testWidgets('body stats → suggest goals → save updates the hub and Overview', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp()))!;
    await tester.pumpWidget(t.app);
    await settle(tester);

    await openSection(tester, 'Body stats');
    await tester.enterText(find.widgetWithText(TextFormField, 'Height'), '178');
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '75');
    await tester.enterText(find.widgetWithText(TextFormField, 'Birth year'), '${AppClock.now().year - 30}');
    await tester.tap(find.text('Male'));
    await tester.scrollUntilVisible(find.text('Moderate'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Moderate'));
    await tester.scrollUntilVisible(find.text('Save'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Save'));
    await step(tester);
    await tester.pageBack();
    await step(tester);
    expect(find.text('178 cm · 75 kg · Moderate'), findsOneWidget);

    await tester.tap(find.text('Goals'));
    await step(tester);
    await tester.scrollUntilVisible(
      find.text('Suggest from body stats'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Suggest from body stats'));
    await step(tester);
    await tester.scrollUntilVisible(find.text('Save'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Save'));
    await step(tester);
    await tester.pageBack();
    await step(tester);
    expect(find.text('2,650 kcal · 3,250 ml water'), findsOneWidget);
  });

  testWidgets('choosing Ocean changes the theme', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp()))!;
    await tester.pumpWidget(t.app);
    await settle(tester);
    await openSection(tester, 'Appearance');
    await tester.tap(find.text('Ocean'));
    await step(tester);
    final ctx = tester.element(find.text('Ocean'));
    expect(Theme.of(ctx).colorScheme.primary, const Color(0xFF0061A4));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/appearance_phone.png'));
  });

  testWidgets('first run: Start saves goals and opens the app', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp(prefs: {'first_run_done': false})))!;
    await tester.pumpWidget(t.app);
    await settle(tester);
    expect(find.text('Welcome to Atharxa'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/first_run_phone.png'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Calories'), '1800');
    await tester.scrollUntilVisible(find.text('Start'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Start'));
    await step(tester);
    expect(find.text('Welcome to Atharxa'), findsNothing);
    expect(find.textContaining('1,800 goal'), findsOneWidget);
  });

  testWidgets('first run: Skip goes straight to the app', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp(prefs: {'first_run_done': false})))!;
    await tester.pumpWidget(t.app);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Skip'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Skip'));
    await step(tester);
    expect(find.text('Overview'), findsWidgets);
  });
}
