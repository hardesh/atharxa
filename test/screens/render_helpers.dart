import 'dart:io';

import 'package:atharxa/data/db.dart';
import 'package:atharxa/main.dart';
import 'package:atharxa/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// Loads Roboto + Material Icons so rendered screenshots show real text.
Future<void> loadFonts() async {
  Future<ByteData> file(String path) async => ByteData.sublistView(await File(path).readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final w in ['400', '500', '700']) {
    roboto.addFont(file('assets/fonts/Roboto-$w.ttf'));
  }
  await roboto.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(file(icons.path))).load();
  }
}

class TestApp {
  TestApp(this.db, this.app);
  final AppDb db;
  final Widget app;
}

/// Builds the real app on a fresh test database. Call inside `tester.runAsync`.
Future<TestApp> buildTestApp({Map<String, Object> prefs = const {}, List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues({'text_scale': 1.0, 'first_run_done': true, ...prefs});
  final sp = await SharedPreferences.getInstance();
  final db = await openTestDb();
  final base = await appOverrides(db: db, prefs: sp, notifications: NotificationService());
  return TestApp(db, ProviderScope(overrides: [...base, ...overrides], child: const App()));
}

/// Lets real async DB work finish, then settles frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
  }
}

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Taps a main destination in the NavigationBar (phone) or NavigationRail (wide).
Future<void> goTo(WidgetTester tester, String label) async {
  final inBar = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  final inRail = find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
  await tester.tap(inBar.evaluate().isNotEmpty ? inBar : inRail);
  await tester.pump();
  await settle(tester);
}

/// Advances animations (dialogs, sheets, snackbars) and lets DB work finish.
/// Use instead of pumpAndSettle when a loading spinner may be on screen.
Future<void> step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
}
