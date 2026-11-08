import 'package:atharxa/state/sync_controller.dart';
import 'package:atharxa/sync/discovery.dart';
import 'package:atharxa/sync/peers.dart';
import 'package:atharxa/ui/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_helpers.dart';

/// Fixed sync state for rendering (no sockets, no mDNS).
class _FakeSync extends SyncController {
  _FakeSync(this.fixed);
  final SyncState fixed;

  @override
  SyncState build() => fixed;
}

DateTime _today(int h, int m) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m);
}

final _onState = SyncState(
  enabled: true,
  deviceName: 'Android phone',
  code: '482913',
  autoSync: true,
  intervalMin: 5,
  listening: true,
  address: '192.168.1.23',
  paired: [
    PairedPeer(
      id: 'mac',
      name: 'MacBook Air',
      host: '192.168.1.42',
      port: 47811,
      lastSyncAt: _today(13, 12),
      lastSent: 4,
      lastReceived: 12,
    ),
  ],
  discovered: const {
    'mac': DiscoveredPeer(id: 'mac', name: 'MacBook Air', host: '192.168.1.42', port: 47811),
    'tab': DiscoveredPeer(id: 'tab', name: 'Pixel Tablet', host: '192.168.1.57', port: 47811),
  },
  busy: true,
  progress: (received: 84, total: 126),
);

Future<void> openYou(WidgetTester tester) async {
  if (find.byType(NavigationRail).evaluate().isNotEmpty) {
    await goTo(tester, 'You');
  } else {
    await tester.tap(find.descendant(of: find.byType(AppTopBar), matching: find.byType(CircleAvatar)));
    await step(tester);
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('you_phone hub + device sync off', (tester) async {
    setSize(tester, const Size(412, 915));
    final t = (await tester.runAsync(() => buildTestApp(prefs: {'text_scale': 1.3})))!;
    await tester.pumpWidget(t.app);
    await settle(tester);
    await openYou(tester);
    expect(find.text('Device sync'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/you_phone.png'));

    await tester.tap(find.text('Device sync'));
    await step(tester);
    expect(find.text('Turn on sync'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/sync_off_phone.png'));
  });

  for (final (name, size, scale) in [
    ('sync_on_phone', const Size(412, 915), 1.3),
    ('sync_on_mac', const Size(1200, 860), 1.0),
  ]) {
    testWidgets(name, (tester) async {
      setSize(tester, size);
      final t = (await tester.runAsync(
        () => buildTestApp(
          prefs: {'text_scale': scale},
          overrides: [syncControllerProvider.overrideWith(() => _FakeSync(_onState))],
        ),
      ))!;
      await tester.pumpWidget(t.app);
      await settle(tester);
      await openYou(tester);
      if (find.byType(NavigationRail).evaluate().isEmpty) {
        await tester.tap(find.text('Device sync'));
        await step(tester);
      }
      expect(find.text('MacBook Air'), findsOneWidget);
      expect(find.text('Pixel Tablet'), findsOneWidget);
      expect(find.text('received 84 of 126'), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    });
  }
}
