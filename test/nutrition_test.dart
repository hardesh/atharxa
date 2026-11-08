import 'package:atharxa/data/food_repo.dart';
import 'package:atharxa/data/models.dart';
import 'package:atharxa/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

FoodItem food(String name, double kcal, double p, double c, double fib, double fat) => FoodItem(
  name: name,
  per100g: Nutrients(kcal: kcal, protein: p, carbs: c, fiber: fib, fat: fat),
);

/// Sample data from DESIGN.md §8.
final oats = food('Rolled oats', 379, 13.2, 67.7, 10.1, 6.5);
final milk = food('Toned milk', 58, 3.1, 4.7, 0, 3.0);
final banana = food('Banana', 89, 1.1, 22.8, 2.6, 0.3);
final paneer = food('Paneer bhurji', 220, 13, 5, 1, 16);
final roti = food('Roti', 300, 10, 46, 5, 8);
final dal = food('Dal tadka', 120, 6, 15, 4, 4);
final chana = food('Roasted chana', 370, 20, 58, 17, 5);
final chai = food('Masala chai', 60, 2, 8, 0, 2);

void main() {
  test('§8 Today: 1,498 eaten, 702 left, macros match', () async {
    final db = await openTestDb();
    final repo = FoodRepo(db);
    const day = '2026-11-08';
    Future<void> add(Meal m, FoodItem f, double g) async {
      final saved = await repo.cache(f);
      await repo.add(FoodRepo.logs, day: day, meal: m, food: saved, grams: g);
    }

    await add(Meal.breakfast, oats, 60);
    await add(Meal.breakfast, milk, 200);
    await add(Meal.breakfast, banana, 120);
    await add(Meal.lunch, paneer, 150);
    await add(Meal.lunch, roti, 80);
    await add(Meal.lunch, dal, 200);
    await add(Meal.snacks, chana, 40);
    await add(Meal.snacks, chai, 150);

    final entries = await repo.entries(FoodRepo.logs, day);
    final t = Nutrients.sum(entries.map((e) => e.totals));
    double mealKcal(Meal m) => entries.where((e) => e.meal == m).fold(0.0, (a, e) => a + e.totals.kcal);

    expect(fmtInt(mealKcal(Meal.breakfast)), '450');
    expect(fmtInt(mealKcal(Meal.lunch)), '810');
    expect(fmtInt(mealKcal(Meal.snacks)), '238');
    expect(fmtInt(t.kcal), '1,498');
    expect(fmtInt(2200 - t.kcal), '702');
    expect(fmtMacro(t.protein), '65.9');
    expect(fmtMacro(t.carbs), '186.9');
    expect(fmtMacro(t.fiber), '29.5');
    expect(fmtMacro(t.fat), '53.7');

    // Adding Rolled Oats (OFF, 389 kcal/100 g) 50 g to Lunch → 195 kcal, Lunch 1,005, 507 left.
    final offOats = FoodItem(
      name: 'Rolled Oats',
      brand: 'Sunvalley Foods',
      barcode: '123',
      source: 'off',
      servingG: 40,
      per100g: const Nutrients(kcal: 389, protein: 13, carbs: 66, fiber: 10, fat: 7),
    );
    expect(fmtInt(offOats.per100g.forGrams(50).kcal), '195');
    await add(Meal.lunch, offOats, 50);
    final after = await repo.entries(FoodRepo.logs, day);
    final lunch = after.where((e) => e.meal == Meal.lunch).fold(0.0, (a, e) => a + e.totals.kcal);
    expect(fmtInt(lunch), '1,005');
    expect(fmtInt(2200 - Nutrients.sum(after.map((e) => e.totals)).kcal), '507');
  });

  test('editing a food does not change past log entries (snapshot)', () async {
    final db = await openTestDb();
    final repo = FoodRepo(db);
    final saved = await repo.cache(roti);
    await repo.add(FoodRepo.logs, day: '2026-11-08', meal: Meal.lunch, food: saved, grams: 80);
    await db.save('foods', {...saved.toRow(), 'kcal': 999});
    final e = (await repo.entries(FoodRepo.logs, '2026-11-08')).single;
    expect(e.totals.kcal, 240);
  });

  test('unknown macros stay unknown, not zero', () {
    const n = Nutrients(kcal: 100);
    expect(fmtMacro(n.forGrams(50).protein), '—');
    expect(nutrientLine(n), '100 kcal · Protein — g · Carbs — g · Fiber — g · Fat — g');
    final sum = Nutrients.sum([n, const Nutrients(kcal: 10, protein: 2)]);
    expect(sum.protein, 2);
  });

  test('online foods are cached once by barcode; My foods sorts recently used first', () async {
    final db = await openTestDb();
    final repo = FoodRepo(db);
    final off = FoodItem(name: 'Oats', barcode: '42', source: 'off', per100g: const Nutrients(kcal: 389));
    final a = await repo.cache(off);
    final b = await repo.cache(off);
    expect(a.id, b.id);
    await repo.cache(banana);
    await repo.add(FoodRepo.logs, day: '2026-11-08', meal: Meal.lunch, food: a, grams: 10);
    final mine = await repo.myFoods();
    expect(mine.first.name, 'Oats');
    expect(mine.length, 2);
  });
}
