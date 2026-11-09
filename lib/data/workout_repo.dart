import 'dart:convert';

import 'db.dart';
import 'models.dart';

/// An exercise in a plan: sets × reps × kg, rest between sets.
class Exercise {
  Exercise(this.row);
  final Map<String, Object?> row;

  String get id => row['id'] as String;
  String get planId => row['plan_id'] as String;
  String get name => row['name'] as String;
  int get sets => (row['sets'] as num).toInt();
  int get reps => (row['reps'] as num).toInt();
  double? get kg => (row['kg'] as num?)?.toDouble();
  int get restS => (row['rest_s'] as num).toInt();

  /// YouTube links the user added for this exercise.
  List<String> get videos =>
      row['videos'] == null ? const [] : (jsonDecode(row['videos'] as String) as List).cast<String>();

  /// "3 × 10 · 16 kg · rest 90 s"
  String get summary => '$sets × $reps · ${kg == null ? 'bodyweight' : '${_kg(kg!)} kg'} · rest ${restS}s';
}

String _kg(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// A plan with its exercises (in order) and the weekdays it repeats on
/// (1 = Monday … 7 = Sunday).
class WorkoutPlan {
  WorkoutPlan(this.row, this.exercises);
  final Map<String, Object?> row;
  final List<Exercise> exercises;

  String get id => row['id'] as String;
  String get name => row['name'] as String;
  Set<int> get days => {
    for (final d in (row['days'] as String? ?? '').split(',').where((s) => s.isNotEmpty)) int.parse(d),
  };

  int get totalSets => exercises.fold(0, (a, e) => a + e.sets);

  /// ~60 s per set of work, the rests between sets, and ~2 min per exercise
  /// for setup/changeover, in minutes (the board's 6-exercise plan → ~45 min).
  int get estimatedMinutes =>
      ((exercises.fold(0, (a, e) => a + e.sets * 60 + (e.sets - 1) * e.restS + 120)) / 60).ceil();

  bool repeatsOn(DateTime d) => days.contains(d.weekday);
}

/// A logged set.
class SetLog {
  SetLog(this.row);
  final Map<String, Object?> row;
  String get exerciseName => row['exercise_name'] as String;
  int get setNo => (row['set_no'] as num).toInt();
  int get reps => (row['reps'] as num).toInt();
  double? get kg => (row['kg'] as num?)?.toDouble();
  double get volume => reps * (kg ?? 0);
}

class WorkoutSession {
  WorkoutSession(this.row, this.sets);
  final Map<String, Object?> row;
  final List<SetLog> sets;

  String get id => row['id'] as String;
  String? get planId => row['plan_id'] as String?;
  String get planName => row['plan_name'] as String;
  String get day => row['day'] as String;
  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch((row['started_at'] as num).toInt());
  DateTime? get endedAt =>
      row['ended_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((row['ended_at'] as num).toInt());
  bool get finished => endedAt != null;
  double? get kcal => (row['kcal'] as num?)?.toDouble();
  bool get addKcalToToday => row['add_kcal_to_today'] == 1;

  double get volume => sets.fold(0.0, (a, s) => a + s.volume);
}

/// Energy estimate: MET 5 (moderate resistance training) × body weight × hours.
double estimateKcal({required Duration duration, double? bodyWeightKg}) =>
    5.0 * (bodyWeightKg ?? 70) * duration.inSeconds / 3600;

class WorkoutRepo {
  WorkoutRepo(this.db);
  final AppDb db;

  static const tables = ['workout_plans', 'exercises', 'sessions', 'set_logs'];

  Future<List<WorkoutPlan>> plans() async {
    final plans = await db.query('workout_plans', orderBy: 'sort, name');
    final ex = await db.query('exercises', orderBy: 'sort');
    return [
      for (final p in plans)
        WorkoutPlan(p, [
          for (final e in ex)
            if (e['plan_id'] == p['id']) Exercise(e),
        ]),
    ];
  }

  /// Saves a plan and its exercises in order; exercises not in [exercises]
  /// are removed. Returns the plan id.
  Future<String> savePlan({
    String? id,
    required String name,
    required Set<int> days,
    required List<Map<String, Object?>> exercises,
  }) async {
    final planId = await db.save('workout_plans', {
      'id': ?id,
      'name': name.trim(),
      'days': (days.toList()..sort()).join(','),
      'sort': 0,
    });
    final keep = <String>{};
    for (final (i, e) in exercises.indexed) {
      keep.add(await db.save('exercises', {...e, 'plan_id': planId, 'sort': i}));
    }
    for (final old in await db.query('exercises', where: 'plan_id = ?', args: [planId])) {
      if (!keep.contains(old['id'])) await db.delete('exercises', old['id'] as String);
    }
    return planId;
  }

  Future<void> deletePlan(WorkoutPlan p) async {
    for (final e in p.exercises) {
      await db.delete('exercises', e.id);
    }
    await db.delete('workout_plans', p.id);
  }

  Future<List<WorkoutSession>> sessionsBetween(String fromDay, String toDay) async {
    final rows = await db.query(
      'sessions',
      where: 'day BETWEEN ? AND ?',
      args: [fromDay, toDay],
      orderBy: 'started_at DESC',
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id']).toList();
    final sets = await db.query(
      'set_logs',
      where: 'session_id IN (${List.filled(ids.length, '?').join(',')})',
      args: ids,
      orderBy: 'done_at',
    );
    return [
      for (final r in rows)
        WorkoutSession(r, [
          for (final s in sets)
            if (s['session_id'] == r['id']) SetLog(s),
        ]),
    ];
  }

  Future<WorkoutSession?> session(String id) async {
    final rows = await db.query('sessions', where: 'id = ?', args: [id]);
    if (rows.isEmpty) return null;
    final sets = await db.query('set_logs', where: 'session_id = ?', args: [id], orderBy: 'done_at');
    return WorkoutSession(rows.first, sets.map(SetLog.new).toList());
  }

  Future<String> startSession(WorkoutPlan p) => db.save('sessions', {
    'plan_id': p.id,
    'plan_name': p.name,
    'day': dayKey(DateTime.now()),
    'started_at': DateTime.now().millisecondsSinceEpoch,
  });

  Future<void> logSet(String sessionId, Exercise e, {required int setNo, required int reps, double? kg}) =>
      db.save('set_logs', {
        'session_id': sessionId,
        'exercise_id': e.id,
        'exercise_name': e.name,
        'set_no': setNo,
        'reps': reps,
        'kg': kg,
        'done_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> finishSession(
    WorkoutSession s, {
    required String? feel,
    required String? notes,
    required double kcal,
    required bool addKcalToToday,
  }) => db.save('sessions', {
    ...AppDb.editable(s.row),
    'ended_at': DateTime.now().millisecondsSinceEpoch,
    'feel': feel,
    'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
    'kcal': kcal,
    'add_kcal_to_today': addKcalToToday ? 1 : 0,
  });

  Future<void> discardSession(String id) => db.delete('sessions', id);

  /// Links a session to the Strava activity it was uploaded as.
  Future<void> setStravaId(String sessionId, String stravaId) async {
    final rows = await db.query('sessions', where: 'id = ?', args: [sessionId]);
    if (rows.isNotEmpty) await db.save('sessions', {...AppDb.editable(rows.first), 'strava_activity_id': stravaId});
  }

  /// Imported Strava activities between two days (inclusive), newest first.
  Future<List<StravaActivity>> stravaBetween(String fromDay, String toDay) async {
    final from = parseDay(fromDay).millisecondsSinceEpoch;
    final to = parseDay(toDay).add(const Duration(days: 1)).millisecondsSinceEpoch;
    final rows = await db.query(
      'strava_activities',
      where: 'start >= ? AND start < ?',
      args: [from, to],
      orderBy: 'start DESC',
    );
    return rows.map(StravaActivity.new).toList();
  }

  /// kcal from today's finished sessions the user chose to add to Today.
  Future<double> kcalAddedOn(String day) async {
    final r = await db.raw(
      'SELECT COALESCE(SUM(kcal),0) AS k FROM sessions WHERE deleted = 0 AND day = ? AND add_kcal_to_today = 1 AND ended_at IS NOT NULL',
      [day],
    );
    return (r.first['k'] as num).toDouble();
  }
}

/// A run, ride or other activity imported from Strava.
class StravaActivity {
  StravaActivity(this.row);
  final Map<String, Object?> row;

  String get type => row['type'] as String;
  String get name => (row['name'] as String?) ?? type;
  DateTime get start => DateTime.fromMillisecondsSinceEpoch((row['start'] as num).toInt());
  double get km => ((row['distance_m'] as num?) ?? 0) / 1000;
  Duration get moving => Duration(seconds: ((row['moving_time_s'] as num?) ?? 0).toInt());

  bool get isRun => const {'Run', 'TrailRun', 'VirtualRun'}.contains(type);
  bool get isRide => const {'Ride', 'MountainBikeRide', 'GravelRide', 'EBikeRide', 'VirtualRide'}.contains(type);
}
