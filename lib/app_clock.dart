import 'package:flutter/foundation.dart';

/// "Now" for everything the user sees (today, this week, this month, meal
/// times). Tests start it at a fixed moment so screens render the same on
/// any day; it then runs at normal speed, so timers still tick.
///
/// Sync and database bookkeeping (edit clocks, signed requests) keep using
/// the real clock.
abstract final class AppClock {
  static DateTime Function() _now = DateTime.now;

  static DateTime now() => _now();

  /// Makes "now" start at [start] and run from there.
  @visibleForTesting
  static void startAt(DateTime start) {
    final real = DateTime.now();
    _now = () => start.add(DateTime.now().difference(real));
  }

  @visibleForTesting
  static void reset() => _now = DateTime.now;
}
