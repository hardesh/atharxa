import 'package:flutter/material.dart';
import 'package:atharxa/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'render_helpers.dart';

/// Rows that arrive from the other device (merge, not a local save) must
/// refresh the visible screen without any interaction.
void main() {
  testWidgets('Overview refreshes when synced rows arrive', (tester) async {
    setSize(tester, const Size(1200, 860));
    final t = (await tester.runAsync(() => buildTestApp()))!;
    await tester.pumpWidget(t.app);
    await settle(tester);
    expect(find.text('0 / 3,000 ml'), findsOneWidget);

    // Simulate the phone's water entry arriving through sync.
    await tester.runAsync(() async {
      final phone = await openTestDb();
      await phone.save('water_logs', {
        'day': dayKey(DateTime.now()),
        'ml': 250,
        'logged_at': DateTime.now().millisecondsSinceEpoch,
        'source': 'today',
      });
      await t.db.merge((await phone.changesPage(0)).rows.where((r) => r.table == 'water_logs'));
    });
    await settle(tester);
    expect(find.text('250 / 3,000 ml'), findsOneWidget);
  });

  testWidgets('Undo snackbar disappears on its own', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp()))!;
    await tester.pumpWidget(t.app);
    await settle(tester);
    await tester.tap(find.text('250 ml'));
    await tester.pump();
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Undo'), findsNothing);
  });
}
