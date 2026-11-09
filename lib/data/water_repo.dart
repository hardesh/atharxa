import 'db.dart';
import 'models.dart';

/// Water entries. `source`: today | water | notification | mac.
class WaterRepo {
  WaterRepo(this.db);
  final AppDb db;

  static const table = 'water_logs';

  Future<List<Map<String, Object?>>> entries(String day) =>
      db.query(table, where: 'day = ?', args: [day], orderBy: 'logged_at DESC');

  Future<int> total(String day) async {
    final r = await db.raw('SELECT COALESCE(SUM(ml),0) AS ml FROM $table WHERE deleted = 0 AND day = ?', [day]);
    return (r.first['ml'] as num).toInt();
  }

  /// Adds [ml] on [date]. The time is now if [date] is today, otherwise noon of that day.
  Future<String> add(DateTime date, int ml, String source) {
    final now = DateTime.now();
    final sameDay = date.year == now.year && date.month == now.month && date.day == now.day;
    final at = sameDay ? now : DateTime(date.year, date.month, date.day, 12);
    return db.save(table, {'day': dayKey(date), 'ml': ml, 'logged_at': at.millisecondsSinceEpoch, 'source': source});
  }

  /// Updates amount and/or time. Moving the time to another day moves the entry too.
  Future<void> update(Map<String, Object?> row, {required int ml, required DateTime at}) =>
      db.save(table, {..._fields(row), 'ml': ml, 'logged_at': at.millisecondsSinceEpoch, 'day': dayKey(at)});

  Future<void> remove(String id) => db.delete(table, id);

  Future<void> restore(Map<String, Object?> row) => db.save(table, _fields(row));

  static Map<String, Object?> _fields(Map<String, Object?> r) => AppDb.editable(r);
}
