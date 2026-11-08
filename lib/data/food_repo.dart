import 'db.dart';
import 'models.dart';

/// Food logging / planning operations shared by Today, Meal plan and
/// notifications. `table` is `food_logs` or `meal_plans`.
class FoodRepo {
  FoodRepo(this.db);
  final AppDb db;

  static const logs = 'food_logs';
  static const plans = 'meal_plans';

  Future<List<FoodEntry>> entries(String table, String day) async {
    final rows = await db.query(table, where: 'day = ?', args: [day], orderBy: 'created_at');
    return rows.map(FoodEntry.new).toList();
  }

  /// Adds [grams] of [food] (snapshotting its per-100 g values). Returns the row id.
  Future<String> add(
    String table, {
    required String day,
    required Meal meal,
    required FoodItem food,
    required double grams,
  }) => db.save(table, {
    'day': day,
    'meal': meal.name,
    'food_id': food.id,
    'name': food.name,
    'brand': food.brand,
    'grams': grams,
    'created_at': DateTime.now().millisecondsSinceEpoch,
    ...food.per100g.toRow(),
  });

  Future<void> update(String table, FoodEntry e, {required double grams, Meal? meal}) =>
      db.save(table, {...e.copyFields(), 'id': e.id, 'grams': grams, 'meal': (meal ?? e.meal).name});

  Future<void> remove(String table, String id) => db.delete(table, id);

  /// Re-inserts a removed entry (Undo).
  Future<void> restore(String table, FoodEntry e) => db.save(table, {...e.copyFields(), 'id': e.id});

  /// Copies entries into another table/day (plan → log, plan day → plan day).
  Future<int> copy(Iterable<FoodEntry> from, String toTable, {String? day}) async {
    var n = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in from) {
      await db.save(toTable, {...e.copyFields(), 'day': ?day, 'created_at': now + n});
      n++;
    }
    return n;
  }

  /// My foods, most recently logged first, then alphabetical.
  Future<List<FoodItem>> myFoods([String query = '']) async {
    final q = query.trim();
    final rows = await db.raw('''
      SELECT f.*, (SELECT MAX(l.created_at) FROM food_logs l WHERE l.food_id = f.id AND l.deleted = 0) AS last_used
      FROM foods f
      WHERE f.deleted = 0 ${q.isEmpty ? '' : 'AND (f.name LIKE ? OR f.brand LIKE ?)'}
      ORDER BY last_used IS NULL, last_used DESC, f.name COLLATE NOCASE
      LIMIT 300''', q.isEmpty ? null : ['%$q%', '%$q%']);
    return rows.map(FoodItem.fromRow).toList();
  }

  /// Saves an online food into My foods (or returns the existing copy by barcode).
  Future<FoodItem> cache(FoodItem f) async {
    if (f.id != null) return f;
    if (f.barcode != null && f.barcode!.isNotEmpty) {
      final existing = await db.query('foods', where: 'barcode = ?', args: [f.barcode]);
      if (existing.isNotEmpty) return FoodItem.fromRow(existing.first);
    }
    final id = await db.save('foods', f.toRow());
    return FoodItem.fromRow({...f.toRow(), 'id': id});
  }

  Future<int> pastEntryCount(String foodId) async {
    final r = await db.raw('SELECT COUNT(*) AS n FROM food_logs WHERE deleted = 0 AND food_id = ?', [foodId]);
    return (r.first['n'] as num).toInt();
  }
}
