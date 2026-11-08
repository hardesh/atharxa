import 'dart:async';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local SQLite database.
///
/// Every *synced* table carries four bookkeeping columns:
///   id          TEXT  – UUID, globally unique across devices
///   updated_at  INT   – hybrid-logical-clock millis of the last edit
///   device_id   TEXT  – device that made the last edit (tie-breaker)
///   deleted     INT   – soft delete flag (tombstone), so deletes sync too
///   rev         INT   – local, monotonically increasing change counter.
///                       Peers ask "give me everything with rev > N".
///
/// Conflict rule: last-writer-wins on (updated_at, device_id).
class AppDb {
  AppDb._(this._db, this.deviceId, this._clock);

  static const syncedTables = [
    'foods',
    'food_logs',
    'meal_plans',
    'water_logs',
    'transactions',
    'categories',
    'workout_plans',
    'exercises',
    'sessions',
    'set_logs',
    'strava_activities',
    'prefs',
  ];

  final Database _db;
  final String deviceId;
  int _clock;
  final _changes = StreamController<String>.broadcast();
  final _localChanges = StreamController<String>.broadcast();
  final Map<String, Set<String>> _columns = {};

  /// Emits the table name whenever a table changes (local edit or sync).
  Stream<String> get changes => _changes.stream;

  /// Emits only for edits made on this device (not rows merged from a peer).
  /// Auto-sync listens to this so a sync never triggers another sync.
  Stream<String> get localChanges => _localChanges.stream;

  /// Opens the app database in the platform's application-support directory.
  static Future<AppDb> open() async {
    final dir = await getApplicationSupportDirectory();
    return openAt(p.join(dir.path, 'atharxa.db'));
  }

  /// Opens (or creates) a database at [path]. Tests pass `inMemoryDatabasePath`
  /// together with an ffi [factory].
  static Future<AppDb> openAt(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => _createSchema(db)),
    );
    final meta = await db.query('sync_meta', where: 'key = ?', whereArgs: ['device_id']);
    String deviceId;
    if (meta.isEmpty) {
      deviceId = const Uuid().v4();
      await db.insert('sync_meta', {'key': 'device_id', 'value': deviceId});
    } else {
      deviceId = meta.first['value'] as String;
    }
    final clockRow = await db.rawQuery(
      'SELECT MAX(m) AS m FROM (${syncedTables.map((t) => 'SELECT MAX(updated_at) AS m FROM $t').join(' UNION ALL ')})',
    );
    final clock = (clockRow.first['m'] as int?) ?? 0;
    final appDb = AppDb._(db, deviceId, clock);
    for (final t in syncedTables) {
      final info = await db.rawQuery('PRAGMA table_info($t)');
      appDb._columns[t] = info.map((r) => r['name'] as String).toSet();
    }
    await appDb._seed();
    return appDb;
  }

  Future<void> close() => _db.close();

  static Future<void> _createSchema(Database db) async {
    const sync =
        'id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, '
        'device_id TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL';
    // Per-100 g nutrition. kcal is required; other macros may be NULL (= unknown,
    // e.g. missing in Open Food Facts) and are shown as "—", not 0.
    const per100 = 'kcal REAL NOT NULL DEFAULT 0, protein REAL, carbs REAL, fiber REAL, fat REAL';
    final batch = db.batch()
      ..execute(
        'CREATE TABLE foods ($sync, name TEXT NOT NULL, brand TEXT, barcode TEXT, '
        'serving_g REAL, source TEXT NOT NULL DEFAULT \'custom\', $per100)',
      )
      // Log and plan entries keep a snapshot of the food's per-100 g values, so
      // editing a food later only affects future entries.
      ..execute(
        'CREATE TABLE food_logs ($sync, day TEXT NOT NULL, meal TEXT NOT NULL, '
        'food_id TEXT, name TEXT NOT NULL, brand TEXT, grams REAL NOT NULL, created_at INTEGER NOT NULL, $per100)',
      )
      ..execute(
        'CREATE TABLE meal_plans ($sync, day TEXT NOT NULL, meal TEXT NOT NULL, '
        'food_id TEXT, name TEXT NOT NULL, brand TEXT, grams REAL NOT NULL, created_at INTEGER NOT NULL, $per100)',
      )
      // source: today | water | notification | mac
      ..execute(
        'CREATE TABLE water_logs ($sync, day TEXT NOT NULL, ml INTEGER NOT NULL, '
        'logged_at INTEGER NOT NULL, source TEXT NOT NULL DEFAULT \'water\')',
      )
      // amount_minor: integer minor units of [currency] (paise, cents; yen has none).
      ..execute(
        'CREATE TABLE transactions ($sync, day TEXT NOT NULL, kind TEXT NOT NULL, '
        'amount_minor INTEGER NOT NULL, currency TEXT NOT NULL, category TEXT NOT NULL, note TEXT)',
      )
      ..execute(
        'CREATE TABLE categories ($sync, name TEXT NOT NULL, kind TEXT NOT NULL, '
        'is_custom INTEGER NOT NULL DEFAULT 0, sort INTEGER NOT NULL DEFAULT 0)',
      )
      // days: comma-separated ISO weekdays (1 = Monday).
      ..execute(
        'CREATE TABLE workout_plans ($sync, name TEXT NOT NULL, days TEXT NOT NULL DEFAULT \'\', '
        'sort INTEGER NOT NULL DEFAULT 0)',
      )
      // videos: JSON array of YouTube URLs added by the user.
      ..execute(
        'CREATE TABLE exercises ($sync, plan_id TEXT NOT NULL, name TEXT NOT NULL, '
        'sets INTEGER NOT NULL DEFAULT 3, reps INTEGER NOT NULL DEFAULT 10, kg REAL, '
        'rest_s INTEGER NOT NULL DEFAULT 90, sort INTEGER NOT NULL DEFAULT 0, videos TEXT)',
      )
      ..execute(
        'CREATE TABLE sessions ($sync, plan_id TEXT, plan_name TEXT NOT NULL, day TEXT NOT NULL, '
        'started_at INTEGER NOT NULL, ended_at INTEGER, feel TEXT, notes TEXT, kcal REAL, '
        'add_kcal_to_today INTEGER NOT NULL DEFAULT 0, strava_activity_id TEXT)',
      )
      ..execute(
        'CREATE TABLE set_logs ($sync, session_id TEXT NOT NULL, exercise_id TEXT, '
        'exercise_name TEXT NOT NULL, set_no INTEGER NOT NULL, reps INTEGER NOT NULL, kg REAL, '
        'done_at INTEGER NOT NULL)',
      )
      ..execute(
        'CREATE TABLE strava_activities ($sync, type TEXT NOT NULL, name TEXT, '
        'start INTEGER NOT NULL, distance_m REAL, moving_time_s INTEGER)',
      )
      ..execute('CREATE TABLE prefs ($sync, value TEXT)')
      // Local-only: device id, rev counter, per-peer sync cursors.
      ..execute('CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT)');
    for (final t in syncedTables) {
      batch.execute('CREATE INDEX idx_${t}_rev ON $t(rev)');
    }
    for (final t in ['food_logs', 'meal_plans', 'water_logs', 'transactions', 'sessions']) {
      batch.execute('CREATE INDEX idx_${t}_day ON $t(day)');
    }
    batch.execute('CREATE INDEX idx_exercises_plan ON exercises(plan_id)');
    batch.execute('CREATE INDEX idx_set_logs_session ON set_logs(session_id)');
    await batch.commit(noResult: true);
  }

  /// Default finance categories. Ids are fixed so both devices seed the same
  /// rows and sync merges them instead of duplicating.
  static const defaultCategories = [
    ('Food', 'expense'),
    ('Groceries', 'expense'),
    ('Transport', 'expense'),
    ('Rent', 'expense'),
    ('Bills', 'expense'),
    ('Shopping', 'expense'),
    ('Health', 'expense'),
    ('Entertainment', 'expense'),
    ('Other', 'expense'),
    ('Salary', 'income'),
    ('Other', 'income'),
  ];

  Future<void> _seed() async {
    if (await getMeta('seeded') != null) return;
    var i = 0;
    for (final (name, kind) in defaultCategories) {
      final id = 'cat-$kind-${name.toLowerCase()}';
      final exists = await _db.query('categories', where: 'id = ?', whereArgs: [id]);
      if (exists.isEmpty) {
        await save('categories', {'id': id, 'name': name, 'kind': kind, 'is_custom': 0, 'sort': i});
      }
      i++;
    }
    await setMeta('seeded', '1');
  }

  // ---------------------------------------------------------------- clock/rev

  int _tick() => _clock = max(DateTime.now().millisecondsSinceEpoch, _clock + 1);

  Future<int> _nextRev(DatabaseExecutor tx) async {
    final r = await tx.query('sync_meta', where: 'key = ?', whereArgs: ['rev']);
    final next = (r.isEmpty ? 0 : int.parse(r.first['value'] as String)) + 1;
    await tx.insert('sync_meta', {'key': 'rev', 'value': '$next'}, conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  Future<int> currentRev() async {
    final r = await _db.query('sync_meta', where: 'key = ?', whereArgs: ['rev']);
    return r.isEmpty ? 0 : int.parse(r.first['value'] as String);
  }

  // ------------------------------------------------------------ local writes

  /// Insert or update a row. Returns the row id.
  Future<String> save(String table, Map<String, Object?> row) async {
    final id = (row['id'] as String?) ?? const Uuid().v4();
    await _db.transaction((tx) async {
      final rev = await _nextRev(tx);
      await tx.insert(table, {
        ...row,
        'id': id,
        'updated_at': _tick(),
        'device_id': deviceId,
        'deleted': 0,
        'rev': rev,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    _changes.add(table);
    _localChanges.add(table);
    return id;
  }

  /// Soft delete (tombstone) so the deletion propagates to the other device.
  Future<void> delete(String table, String id) async {
    await _db.transaction((tx) async {
      final rev = await _nextRev(tx);
      await tx.update(
        table,
        {'deleted': 1, 'updated_at': _tick(), 'device_id': deviceId, 'rev': rev},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    _changes.add(table);
    _localChanges.add(table);
  }

  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? args,
    String? orderBy,
    int? limit,
  }) => _db.query(
    table,
    where: where == null ? 'deleted = 0' : 'deleted = 0 AND ($where)',
    whereArgs: args,
    orderBy: orderBy,
    limit: limit,
  );

  Future<List<Map<String, Object?>>> raw(String sql, [List<Object?>? args]) => _db.rawQuery(sql, args);

  // ------------------------------------------------------------------ prefs

  Future<String?> getPref(String key) async {
    final r = await query('prefs', where: 'id = ?', args: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setPref(String key, String value) => save('prefs', {'id': key, 'value': value});

  Future<String?> getMeta(String key) async {
    final r = await _db.query('sync_meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) =>
      _db.insert('sync_meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // -------------------------------------------------------------------- sync

  /// One page of rows (tombstones included) changed after [sinceRev], ordered
  /// by `rev` across all synced tables. Rows last edited by [excludeDevice]
  /// are skipped: that peer already has them (or something newer), so this
  /// avoids echoing a peer's own edits back to it.
  ///
  /// [next] is the cursor to resume from; [more] says whether rows remain.
  Future<({List<SyncRow> rows, int next, bool more})> changesPage(
    int sinceRev, {
    int limit = 500,
    String? excludeDevice,
  }) async {
    final where = excludeDevice == null ? 'rev > ?' : 'rev > ? AND device_id != ?';
    final args = [sinceRev, ?excludeDevice];
    final all = <SyncRow>[];
    for (final t in syncedTables) {
      // limit + 1 per table so a full page from one table still reports `more`.
      final rows = await _db.query(t, where: where, whereArgs: args, orderBy: 'rev', limit: limit + 1);
      all.addAll(rows.map((r) => SyncRow(t, r)));
    }
    all.sort((a, b) => a.rev.compareTo(b.rev));
    final more = all.length > limit;
    final page = all.take(limit).toList();
    final next = more ? page.last.rev : await currentRev();
    return (rows: page, next: next, more: more);
  }

  /// Number of rows a [changesPage] walk from [sinceRev] would return.
  Future<int> countChanges(int sinceRev, {String? excludeDevice}) async {
    final where = excludeDevice == null ? 'rev > ?' : 'rev > ? AND device_id != ?';
    var n = 0;
    for (final t in syncedTables) {
      final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM $t WHERE $where', [sinceRev, ?excludeDevice]);
      n += (r.first['n'] as num).toInt();
    }
    return n;
  }

  /// Merge rows from a peer. Newer (updated_at, device_id) wins; unknown
  /// tables and columns are ignored. Returns how many rows were applied.
  Future<int> merge(Iterable<SyncRow> rows) async {
    var applied = 0;
    final touched = <String>{};
    await _db.transaction((tx) async {
      for (final r in rows) {
        final cols = _columns[r.table];
        if (cols == null) continue;
        final row = <String, Object?>{
          for (final e in r.row.entries)
            if (cols.contains(e.key) && e.key != 'rev') e.key: e.value,
        };
        final id = row['id'] as String?;
        final ts = (row['updated_at'] as num?)?.toInt();
        final dev = row['device_id'] as String?;
        if (id == null || ts == null || dev == null) continue;
        final cur = await tx.query(r.table, columns: ['updated_at', 'device_id'], where: 'id = ?', whereArgs: [id]);
        if (cur.isNotEmpty) {
          final curTs = cur.first['updated_at'] as int;
          final curDev = cur.first['device_id'] as String;
          final newer = ts > curTs || (ts == curTs && dev.compareTo(curDev) > 0);
          if (!newer) continue;
        }
        row['rev'] = await _nextRev(tx);
        await tx.insert(r.table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        _clock = max(_clock, ts);
        applied++;
        touched.add(r.table);
      }
    });
    for (final t in touched) {
      _changes.add(t);
    }
    return applied;
  }
}

/// A row of a synced table, as exchanged between devices.
class SyncRow {
  SyncRow(this.table, this.row);
  final String table;
  final Map<String, Object?> row;

  int get rev => (row['rev'] as num?)?.toInt() ?? 0;

  Map<String, Object?> toJson() => {'t': table, 'r': Map.of(row)..remove('rev')};

  static SyncRow fromJson(Map<String, dynamic> j) => SyncRow(j['t'] as String, (j['r'] as Map).cast<String, Object?>());
}
