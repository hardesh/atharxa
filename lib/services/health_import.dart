import 'dart:io';

import 'package:health/health.dart';

import '../app_clock.dart';
import '../data/db.dart';
import '../data/workout_repo.dart';

/// Workouts from Health Connect (Android): whatever Strava (GPS activities),
/// Pixel Watch / Google Health or Fitbit write there. Read-only; the rows
/// sync to the Mac like other data. The only file that uses `health`.
class HealthImport {
  HealthImport() : _health = Health();
  final Health _health;
  bool _configured = false;

  /// Types read for a workout's distance, calories and steps.
  static const _types = [
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
  ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Health Connect is on this device (Android only; built into Android 14+).
  Future<bool> available() async {
    if (!Platform.isAndroid) return false;
    await _configure();
    return await _health.getHealthConnectSdkStatus() == HealthConnectSdkStatus.sdkAvailable;
  }

  /// Whether the user already allowed reading workouts.
  Future<bool> granted() async {
    await _configure();
    return await _health.hasPermissions(_types) ?? false;
  }

  /// Shows Android's Health Connect permission screen (workouts, then
  /// history so the first import can reach back 90 days).
  Future<bool> requestAccess() async {
    await _configure();
    final ok = await _health.requestAuthorization(_types);
    if (ok && !await _health.isHealthDataHistoryAuthorized()) {
      await _health.requestHealthDataHistoryAuthorization();
    }
    return ok;
  }

  /// Imports workouts that started after [since]; returns how many rows were
  /// new or changed.
  Future<int> importSince(AppDb db, DateTime since) async {
    await _configure();
    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.WORKOUT],
      startTime: since,
      endTime: AppClock.now(),
    );
    var n = 0;
    for (final p in points) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      final row = activityRow(
        uuid: p.uuid,
        type: v.workoutActivityType.name,
        from: p.dateFrom,
        to: p.dateTo,
        distanceM: v.totalDistance?.toDouble(),
        kcal: v.totalEnergyBurned?.toDouble(),
        sourcePackage: p.sourceName,
      );
      if (await db.saveIfChanged(Activity.table, row)) n++;
    }
    return n;
  }

  /// An `activities` row. The id comes from Health Connect's record id, so
  /// re-imports update instead of duplicating.
  static Map<String, Object?> activityRow({
    required String uuid,
    required String type,
    required DateTime from,
    required DateTime to,
    double? distanceM,
    double? kcal,
    String? sourcePackage,
  }) {
    final source = appName(sourcePackage);
    return {
      'id': 'hc-$uuid',
      'type': type,
      'name': null,
      'source': source,
      'start': from.millisecondsSinceEpoch,
      'distance_m': distanceM,
      'moving_time_s': to.difference(from).inSeconds,
      'kcal': kcal,
    };
  }

  /// "Strava" for com.strava; known fitness apps by name, else the package.
  static String? appName(String? package) => switch (package) {
    null || '' => null,
    'com.strava' => 'Strava',
    'com.google.android.apps.fitness' => 'Google Fit',
    'com.google.android.apps.healthdata' => 'Health Connect',
    'com.fitbit.FitbitMobile' => 'Fitbit',
    'com.google.android.apps.wearables.maestro.companion' ||
    'com.google.android.wearable.healthservices' => 'Pixel Watch',
    'com.samsung.android.app.health' || 'com.sec.android.app.shealth' => 'Samsung Health',
    'com.garmin.android.apps.connectmobile' => 'Garmin Connect',
    _ when package.startsWith('com.google.android.apps.health') => 'Google Health',
    _ => package,
  };
}
