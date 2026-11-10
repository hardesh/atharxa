import 'package:atharxa/app_clock.dart';
import 'package:atharxa/data/models.dart';
import 'package:atharxa/data/water_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_helpers.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('past days are locked until unlocked; future days take no logs', (tester) async {
    setSize(tester, const Size(412, 1200));
    final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': 1.0})))!;
    final yesterday = dayKey(AppClock.now().subtract(const Duration(days: 1)));
    await tester.runAsync(() => WaterRepo(t.db).add(parseDay(yesterday), 500, 'water'));
    await tester.pumpWidget(t.app);
    await settle(tester);

    // Today: everything editable, no bar.
    expect(find.byTooltip('Add food to Breakfast'), findsOneWidget);
    expect(find.text('250 ml'), findsOneWidget);
    expect(find.textContaining('locked'), findsNothing);

    // Yesterday: locked, read-only.
    await tester.tap(find.byTooltip('Previous day'));
    await step(tester);
    expect(find.text('Past day · locked'), findsOneWidget);
    expect(find.byTooltip('Add food to Breakfast'), findsNothing);
    expect(find.text('250 ml'), findsNothing);

    // Unlock: editable again; Lock puts it back.
    await tester.tap(find.text('Unlock to edit'));
    await step(tester);
    expect(find.text('Editing a past day'), findsOneWidget);
    expect(find.byTooltip('Add food to Breakfast'), findsOneWidget);
    await tester.tap(find.text('Lock'));
    await step(tester);
    expect(find.byTooltip('Add food to Breakfast'), findsNothing);

    // The Water screen honours the same lock: entries shown, not editable.
    await goTo(tester, 'Water');
    expect(find.text('Past day · locked'), findsOneWidget);
    expect(find.text('+250 ml'), findsNothing);
    expect(find.text('500 ml'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    // Tomorrow (two steps forward): nothing can be logged, and no unlock.
    await tester.tap(find.byTooltip('Next day'));
    await step(tester);
    await tester.tap(find.byTooltip('Next day'));
    await step(tester);
    expect(find.textContaining('Future day'), findsOneWidget);
    expect(find.text('Unlock to edit'), findsNothing);
    expect(find.text('+250 ml'), findsNothing);
  });
}
