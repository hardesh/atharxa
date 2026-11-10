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
    'activities',
    'prefs',
    'chats',
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
  ///
  /// Background work (Android sync job, notification actions) must pass
  /// [separateConnection]: they can run inside the app's process, and
  /// sqflite otherwise hands every open of the same file the *same*
  /// connection — closing it would close the app's database too
  /// ("database_closed").
  static Future<AppDb> open({bool separateConnection = false}) async {
    final dir = await getApplicationSupportDirectory();
    return openAt(p.join(dir.path, 'atharxa.db'), separateConnection: separateConnection);
  }

  /// Opens (or creates) a database at [path]. Tests pass `inMemoryDatabasePath`
  /// together with an ffi [factory].
  static Future<AppDb> openAt(String path, {DatabaseFactory? factory, bool separateConnection = false}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await _createSchema(db);
          await _upgrade(db, 1);
        },
        onUpgrade: (db, from, _) => _upgrade(db, from),
        singleInstance: !separateConnection,
      ),
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

  /// Bookkeeping columns every synced table has.
  static const _syncCols =
      'id TEXT PRIMARY KEY, updated_at INTEGER NOT NULL, '
      'device_id TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, rev INTEGER NOT NULL';

  static Future<void> _createSchema(Database db) async {
    // Per-100 g nutrition. kcal is required; other macros may be NULL (= unknown,
    // e.g. missing in Open Food Facts) and are shown as "—", not 0.
    const per100 = 'kcal REAL NOT NULL DEFAULT 0, protein REAL, carbs REAL, fiber REAL, fat REAL';
    final batch = db.batch()
      ..execute(
        'CREATE TABLE foods ($_syncCols, name TEXT NOT NULL, brand TEXT, barcode TEXT, '
        'serving_g REAL, source TEXT NOT NULL DEFAULT \'custom\', $per100)',
      )
      // Log and plan entries keep a snapshot of the food's per-100 g values, so
      // editing a food later only affects future entries.
      ..execute(
        'CREATE TABLE food_logs ($_syncCols, day TEXT NOT NULL, meal TEXT NOT NULL, '
        'food_id TEXT, name TEXT NOT NULL, brand TEXT, grams REAL NOT NULL, created_at INTEGER NOT NULL, $per100)',
      )
      ..execute(
        'CREATE TABLE meal_plans ($_syncCols, day TEXT NOT NULL, meal TEXT NOT NULL, '
        'food_id TEXT, name TEXT NOT NULL, brand TEXT, grams REAL NOT NULL, created_at INTEGER NOT NULL, $per100)',
      )
      // source: today | water | notification | mac
      ..execute(
        'CREATE TABLE water_logs ($_syncCols, day TEXT NOT NULL, ml INTEGER NOT NULL, '
        'logged_at INTEGER NOT NULL, source TEXT NOT NULL DEFAULT \'water\')',
      )
      // amount_minor: integer minor units of [currency] (paise, cents; yen has none).
      ..execute(
        'CREATE TABLE transactions ($_syncCols, day TEXT NOT NULL, kind TEXT NOT NULL, '
        'amount_minor INTEGER NOT NULL, currency TEXT NOT NULL, category TEXT NOT NULL, note TEXT)',
      )
      ..execute(
        'CREATE TABLE categories ($_syncCols, name TEXT NOT NULL, kind TEXT NOT NULL, '
        'is_custom INTEGER NOT NULL DEFAULT 0, sort INTEGER NOT NULL DEFAULT 0)',
      )
      // days: comma-separated ISO weekdays (1 = Monday).
      ..execute(
        'CREATE TABLE workout_plans ($_syncCols, name TEXT NOT NULL, days TEXT NOT NULL DEFAULT \'\', '
        'sort INTEGER NOT NULL DEFAULT 0)',
      )
      // videos: JSON array of YouTube URLs added by the user.
      ..execute(
        'CREATE TABLE exercises ($_syncCols, plan_id TEXT NOT NULL, name TEXT NOT NULL, '
        'sets INTEGER NOT NULL DEFAULT 3, reps INTEGER NOT NULL DEFAULT 10, kg REAL, '
        'rest_s INTEGER NOT NULL DEFAULT 90, sort INTEGER NOT NULL DEFAULT 0, videos TEXT)',
      )
      ..execute(
        'CREATE TABLE sessions ($_syncCols, plan_id TEXT, plan_name TEXT NOT NULL, day TEXT NOT NULL, '
        'started_at INTEGER NOT NULL, ended_at INTEGER, feel TEXT, notes TEXT, kcal REAL, '
        'add_kcal_to_today INTEGER NOT NULL DEFAULT 0, strava_activity_id TEXT)',
      )
      ..execute(
        'CREATE TABLE set_logs ($_syncCols, session_id TEXT NOT NULL, exercise_id TEXT, '
        'exercise_name TEXT NOT NULL, set_no INTEGER NOT NULL, reps INTEGER NOT NULL, kg REAL, '
        'done_at INTEGER NOT NULL)',
      )
      ..execute(
        'CREATE TABLE strava_activities ($_syncCols, type TEXT NOT NULL, name TEXT, '
        'start INTEGER NOT NULL, distance_m REAL, moving_time_s INTEGER)',
      )
      ..execute('CREATE TABLE prefs ($_syncCols, value TEXT)')
      // Local-only: device id, rev counter, per-peer sync cursors.
      ..execute('CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT)');
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

  /// Schema changes after version 1, applied to new and existing databases.
  static Future<void> _upgrade(Database db, int from) async {
    if (from < 2) {
      // Assistant chats: messages is a JSON array of {"u": fromUser, "t": text}.
      await db.execute(
        'CREATE TABLE chats ($_syncCols, title TEXT NOT NULL, messages TEXT NOT NULL, last_at INTEGER NOT NULL)',
      );
    }
    if (from < 3) {
      // Imported workouts used to be Strava-only; they now come from any app
      // through Health Connect. source = the app that recorded it.
      await db.execute('ALTER TABLE strava_activities RENAME TO activities');
      await db.execute('DROP INDEX IF EXISTS idx_strava_activities_rev');
      await db.execute('ALTER TABLE activities ADD COLUMN source TEXT');
      await db.execute('ALTER TABLE activities ADD COLUMN kcal REAL');
    }
    // Every synced table pages changes by rev (tables added above included).
    for (final t in syncedTables) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${t}_rev ON $t(rev)');
    }
  }

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

  Future<int> _readRev(DatabaseExecutor tx) async {
    final r = await tx.query('sync_meta', where: 'key = ?', whereArgs: ['rev']);
    return r.isEmpty ? 0 : int.parse(r.first['value'] as String);
  }

  Future<int> _nextRev(DatabaseExecutor tx) async {
    final next = await _readRev(tx) + 1;
    await tx.insert('sync_meta', {'key': 'rev', 'value': '$next'}, conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  Future<int> currentRev() => _readRev(_db);

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
    _emit(table, local: true);
    return id;
  }

  /// Saves [rows] (each with an id) in one transaction, skipping rows whose
  /// live copy already has the same values, so re-imports don't re-sync
  /// them. Notifies listeners once. Returns how many were written.
  Future<int> saveAllIfChanged(String table, List<Map<String, Object?>> rows) async {
    var written = 0;
    await _db.transaction((tx) async {
      for (final row in rows) {
        final existing = await tx.query(table, where: 'id = ? AND deleted = 0', whereArgs: [row['id']]);
        if (existing.isNotEmpty && row.entries.every((e) => existing.first[e.key] == e.value)) continue;
        await tx.insert(table, {
          ...row,
          'updated_at': _tick(),
          'device_id': deviceId,
          'deleted': 0,
          'rev': await _nextRev(tx),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        written++;
      }
    });
    if (written > 0) _emit(table, local: true);
    return written;
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
    _emit(table, local: true);
  }

  /// Sync bookkeeping columns, managed by [save]/[delete]/[merge].
  static const bookkeeping = {'updated_at', 'device_id', 'deleted', 'rev'};

  /// A copy of [row] without bookkeeping (and without `id` unless [keepId]),
  /// ready to pass back to [save] — to update it, restore it, or duplicate it.
  static Map<String, Object?> editable(Map<String, Object?> row, {bool keepId = true}) =>
      Map.of(row)..removeWhere((k, _) => bookkeeping.contains(k) || (!keepId && k == 'id'));

  /// True once anything was logged or a goal was set (used to skip first run).
  Future<bool> hasUserData() async {
    final r = await _db.rawQuery(
      "SELECT (SELECT COUNT(*) FROM food_logs) + (SELECT COUNT(*) FROM water_logs) + "
      "(SELECT COUNT(*) FROM transactions) + (SELECT COUNT(*) FROM prefs WHERE id LIKE 'goal_%') AS n",
    );
    return (r.first['n'] as num) > 0;
  }

  /// Another process (e.g. a notification action in a background isolate)
  /// may have written to the database: re-query everything.
  void notifyExternalChange() {
    for (final t in syncedTables) {
      _changes.add(t);
    }
  }

  void _emit(String table, {required bool local}) {
    _changes.add(table);
    if (local) _localChanges.add(table);
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

  /// `rev > since` (and not last edited by [excludeDevice]) as SQL + args.
  static (String, List<Object?>) _sinceFilter(int sinceRev, String? excludeDevice) =>
      excludeDevice == null ? ('rev > ?', [sinceRev]) : ('rev > ? AND device_id != ?', [sinceRev, excludeDevice]);

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
    final (where, args) = _sinceFilter(sinceRev, excludeDevice);
    // One cheap rev-only query finds the page boundary, so each table read
    // below fetches just the rows that belong to this page.
    final union = syncedTables.map((t) => 'SELECT rev FROM $t WHERE $where').join(' UNION ALL ');
    final revs = await _db.rawQuery('SELECT rev FROM ($union) ORDER BY rev LIMIT ?', [
      for (final _ in syncedTables) ...args,
      limit + 1,
    ]);
    final more = revs.length > limit;
    if (revs.isEmpty) return (rows: const <SyncRow>[], next: await currentRev(), more: false);
    final upTo = (revs[(more ? limit : revs.length) - 1]['rev'] as num).toInt();
    final page = <SyncRow>[];
    for (final t in syncedTables) {
      final rows = await _db.query(t, where: '$where AND rev <= ?', whereArgs: [...args, upTo]);
      page.addAll(rows.map((r) => SyncRow(t, r)));
    }
    page.sort((a, b) => a.rev.compareTo(b.rev));
    return (rows: page, next: more ? upTo : await currentRev(), more: more);
  }

  /// Every live row of every synced table (for backups).
  Future<List<SyncRow>> allRows() async => [
    for (final t in syncedTables)
      for (final r in await _db.query(t, where: 'deleted = 0')) SyncRow(t, r),
  ];

  /// Live (not deleted) rows per table, in one query.
  Future<Map<String, int>> countLive(Iterable<String> tables) async {
    final r = await _db.rawQuery(
      tables.map((t) => "SELECT '$t' AS t, COUNT(*) AS n FROM $t WHERE deleted = 0").join(' UNION ALL '),
    );
    return {for (final row in r) row['t'] as String: (row['n'] as num).toInt()};
  }

  /// Number of rows a [changesPage] walk from [sinceRev] would return.
  Future<int> countChanges(int sinceRev, {String? excludeDevice}) async {
    final (where, args) = _sinceFilter(sinceRev, excludeDevice);
    final sum = syncedTables.map((t) => '(SELECT COUNT(*) FROM $t WHERE $where)').join(' + ');
    final r = await _db.rawQuery('SELECT $sum AS n', [for (final _ in syncedTables) ...args]);
    return (r.first['n'] as num).toInt();
  }

  /// Merge rows from a peer. Newer (updated_at, device_id) wins; unknown
  /// tables and columns are ignored. Returns how many rows were applied.
  ///
  /// [cursor] (a sync_meta key/value) is written in the same transaction, so
  /// a resumed sync never skips or re-applies a page.
  Future<int> merge(Iterable<SyncRow> rows, {(String, String)? cursor}) async {
    // Group incoming rows by table, keeping only known columns.
    final byTable = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      final cols = _columns[r.table];
      if (cols == null) continue;
      final row = <String, Object?>{
        for (final e in r.row.entries)
          if (cols.contains(e.key) && e.key != 'rev') e.key: e.value,
      };
      if (row['id'] is String && row['updated_at'] is num && row['device_id'] is String) {
        (byTable[r.table] ??= []).add(row);
      }
    }
    final touched = <String>{};
    var applied = 0;
    await _db.transaction((tx) async {
      var rev = await _readRev(tx);
      final batch = tx.batch();
      for (final MapEntry(key: table, value: incoming) in byTable.entries) {
        // Current versions of all incoming ids in one query.
        final ids = incoming.map((r) => r['id']).toList();
        final current = {
          for (final c in await tx.query(
            table,
            columns: ['id', 'updated_at', 'device_id'],
            where: 'id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: ids,
          ))
            c['id'] as String: (c['updated_at'] as int, c['device_id'] as String),
        };
        for (final row in incoming) {
          final ts = (row['updated_at'] as num).toInt();
          final dev = row['device_id'] as String;
          final cur = current[row['id'] as String];
          if (cur != null && !(ts > cur.$1 || (ts == cur.$1 && dev.compareTo(cur.$2) > 0))) continue;
          current[row['id'] as String] = (ts, dev);
          batch.insert(table, {...row, 'rev': ++rev}, conflictAlgorithm: ConflictAlgorithm.replace);
          _clock = max(_clock, ts);
          applied++;
          touched.add(table);
        }
      }
      batch.insert('sync_meta', {'key': 'rev', 'value': '$rev'}, conflictAlgorithm: ConflictAlgorithm.replace);
      if (cursor != null) {
        batch.insert('sync_meta', {'key': cursor.$1, 'value': cursor.$2}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    for (final t in touched) {
      _emit(t, local: false);
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
