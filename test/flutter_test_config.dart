import 'dart:async';

import 'package:atharxa/app_clock.dart';

/// Every test sees the same "now" (a Monday at lunch time), so screens and
/// screenshots don't change with the day the suite runs.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppClock.startAt(DateTime(2026, 11, 9, 12, 30));
  await testMain();
}
