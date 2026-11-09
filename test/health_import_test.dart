import 'package:atharxa/data/workout_repo.dart';
import 'package:atharxa/services/health_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final from = DateTime(2026, 11, 8, 7);

  test('a Health Connect workout becomes an activities row', () {
    final row = HealthImport.activityRow(
      uuid: 'abc',
      type: 'RUNNING',
      from: from,
      to: from.add(const Duration(minutes: 31)),
      distanceM: 5230,
      kcal: 410,
      sourcePackage: 'com.strava',
    );
    expect(row['id'], 'hc-abc');
    expect(row['source'], 'Strava');
    expect(row['moving_time_s'], 31 * 60);
    final a = Activity(row);
    expect([a.isRun, a.isRide, a.km, a.kcal, a.typeLabel], [true, false, 5.23, 410.0, 'Running']);
  });

  test('app names', () {
    expect(HealthImport.appName('com.fitbit.FitbitMobile'), 'Fitbit');
    expect(HealthImport.appName('com.google.android.apps.healthconnect.extra'), 'Google Health');
    expect(HealthImport.appName('org.example.tracker'), 'org.example.tracker');
    expect(HealthImport.appName(null), isNull);
  });

  Activity act(String id, String type, int startMin, int minutes, {double? m, double? kcal}) => Activity(
    HealthImport.activityRow(
      uuid: id,
      type: type,
      from: from.add(Duration(minutes: startMin)),
      to: from.add(Duration(minutes: startMin + minutes)),
      distanceM: m,
      kcal: kcal,
    ),
  );

  test('the same workout from two apps is shown once, keeping the richer one', () {
    final merged = Activity.merged([
      act('strava', 'RUNNING', 0, 30, m: 5000, kcal: 400),
      act('google', 'RUNNING', 1, 29, kcal: 380), // copy without distance
      act('ride', 'BIKING', 0, 30, m: 20000), // same time, different sport
      act('later', 'RUNNING', 120, 30, m: 4000), // another run
    ]);
    expect(merged.map((a) => a.row['id']), ['hc-strava', 'hc-ride', 'hc-later']);
  });
}
