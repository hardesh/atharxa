import 'package:atharxa/state/data_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../finance_test.dart' show seedNovember;
import 'render_helpers.dart';

/// Shows November 2026 (the DESIGN.md §8 sample month).
class _November extends FinanceMonth {
  @override
  DateTime build() => DateTime(2026, 11);
}

void main() {
  setUpAll(loadFonts);

  for (final (name, size, scale) in [
    ('finance_phone', const Size(412, 915), 1.3),
    ('finance_mac', const Size(1200, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      setSize(tester, size);
      final t = (await tester.runAsync(
        () => buildTestApp(
          prefs: {'text_scale': scale},
          overrides: [financeMonthSelectedProvider.overrideWith(_November.new)],
        ),
      ))!;
      await tester.runAsync(() => seedNovember(t.db));
      await tester.pumpWidget(t.app);
      await settle(tester);
      await goTo(tester, 'Finance');
      await step(tester);
      expect(find.text('₹1,35,000'), findsOneWidget);
      expect(find.text('₹45,139'), findsWidgets);
      expect(find.text('₹89,861'), findsOneWidget);
      expect(find.text(r'USD: expenses $19.99 · balance −$19.99'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    });
  }

  testWidgets('add an expense from the sheet; Undo removes it', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': 1.0})))!;
    await tester.pumpWidget(t.app);
    await settle(tester);
    await goTo(tester, 'Finance');
    await step(tester); // let the FAB finish appearing
    expect(find.textContaining('No transactions in'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await step(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1150');
    await tester.tap(find.text('Transport'));
    await tester.pump();
    await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -400));
    await step(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/finance_sheet_phone.png'));
    await tester.tap(find.text('Save expense'));
    await step(tester);
    expect(find.text('Expense saved · ₹1,150 Transport'), findsOneWidget);
    expect(find.text('−₹1,150'), findsNWidgets(3)); // balance, day net, row

    await tester.tap(find.text('Undo'));
    await step(tester);
    expect(find.textContaining('No transactions in'), findsOneWidget);
  });
}
