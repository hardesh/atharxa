import 'dart:math';
import 'package:intl/intl.dart';

import 'db.dart';
import '../app_clock.dart';

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime parseDay(String key) => DateTime.parse(key);

double? _n(Object? v) => (v as num?)?.toDouble();

/// kcal + macros. Macros are nullable: `null` means unknown (e.g. missing in
/// Open Food Facts). Sums treat unknown as "contributes nothing" but stay
/// `null` only when every part is unknown.
class Nutrients {
  const Nutrients({this.kcal = 0, this.protein, this.carbs, this.fiber, this.fat});

  static const zero = Nutrients(protein: 0, carbs: 0, fiber: 0, fat: 0);

  final double kcal;
  final double? protein, carbs, fiber, fat;

  factory Nutrients.fromRow(Map<String, Object?> r) => Nutrients(
    kcal: _n(r['kcal']) ?? 0,
    protein: _n(r['protein']),
    carbs: _n(r['carbs']),
    fiber: _n(r['fiber']),
    fat: _n(r['fat']),
  );

  Map<String, Object?> toRow() => {'kcal': kcal, 'protein': protein, 'carbs': carbs, 'fiber': fiber, 'fat': fat};

  /// value = per100 × grams / 100 (DESIGN.md §7.1), full precision.
  Nutrients forGrams(double grams) => scale(grams / 100);

  Nutrients scale(double f) => Nutrients(
    kcal: kcal * f,
    protein: protein == null ? null : protein! * f,
    carbs: carbs == null ? null : carbs! * f,
    fiber: fiber == null ? null : fiber! * f,
    fat: fat == null ? null : fat! * f,
  );

  static double? _add(double? a, double? b) => a == null ? b : (b == null ? a : a + b);

  Nutrients operator +(Nutrients o) => Nutrients(
    kcal: kcal + o.kcal,
    protein: _add(protein, o.protein),
    carbs: _add(carbs, o.carbs),
    fiber: _add(fiber, o.fiber),
    fat: _add(fat, o.fat),
  );

  static Nutrients sum(Iterable<Nutrients> xs) => xs.fold(zero, (a, b) => a + b);
}

/// A food with nutrition per 100 g, from My foods or a remote source.
class FoodItem {
  FoodItem({
    this.id,
    required this.name,
    this.brand,
    this.barcode,
    this.servingG,
    required this.per100g,
    this.source = 'custom',
  });

  final String? id; // null until saved locally
  final String name;
  final String? brand, barcode;
  final double? servingG;
  final Nutrients per100g;
  final String source; // custom | off | (later) ai

  factory FoodItem.fromRow(Map<String, Object?> r) => FoodItem(
    id: r['id'] as String,
    name: r['name'] as String,
    brand: r['brand'] as String?,
    barcode: r['barcode'] as String?,
    servingG: _n(r['serving_g']),
    per100g: Nutrients.fromRow(r),
    source: r['source'] as String? ?? 'custom',
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'name': name,
    'brand': brand,
    'barcode': barcode,
    'serving_g': servingG,
    'source': source,
    ...per100g.toRow(),
  };

  String get sourceLabel => source == 'off' ? 'Open Food Facts' : 'My foods';
}

/// A row of food_logs or meal_plans: grams + a per-100 g snapshot.
class FoodEntry {
  FoodEntry(this.row);
  final Map<String, Object?> row;

  String get id => row['id'] as String;
  String get name => row['name'] as String;
  String? get brand => row['brand'] as String?;
  Meal get meal => Meal.parse(row['meal'] as String);
  double get grams => (row['grams'] as num).toDouble();
  Nutrients get per100 => Nutrients.fromRow(row);
  Nutrients get totals => per100.forGrams(grams);

  /// Fields to copy when duplicating into another table/day.
  Map<String, Object?> copyFields() => AppDb.editable(row, keepId: false);
}

enum Meal {
  breakfast('Breakfast'),
  lunch('Lunch'),
  snacks('Snacks'),
  dinner('Dinner');

  const Meal(this.label);
  final String label;

  static Meal parse(String v) => Meal.values.firstWhere((m) => m.name == v.toLowerCase(), orElse: () => Meal.snacks);
}

/// Daily goals (synced). Defaults from DESIGN.md §5 You › Goals; Fat = 75 g (user decision).
class Goals {
  const Goals({
    this.kcal = 2200,
    this.waterMl = 3000,
    this.protein = 120,
    this.carbs = 250,
    this.fiber = 30,
    this.fat = 75,
  });

  final double kcal, protein, carbs, fiber, fat;
  final int waterMl;

  Goals copyWith({double? kcal}) =>
      Goals(kcal: kcal ?? this.kcal, waterMl: waterMl, protein: protein, carbs: carbs, fiber: fiber, fat: fat);
}

enum Sex { female, male }

/// Activity level → multiplier on BMR (common TDEE factors).
enum ActivityLevel {
  sedentary('Sedentary', 'Little or no exercise', 1.2, 0),
  light('Light', 'Exercise 1–3 days a week', 1.375, 250),
  moderate('Moderate', 'Exercise 3–5 days a week', 1.55, 500),
  active('Active', 'Exercise 6–7 days a week', 1.725, 750),
  veryActive('Very active', 'Hard exercise or a physical job', 1.9, 1000);

  const ActivityLevel(this.label, this.description, this.factor, this.extraWaterMl);
  final String label, description;
  final double factor;

  /// Extra water for sweat on training days, averaged over the week.
  final int extraWaterMl;

  static ActivityLevel parse(String? v) =>
      ActivityLevel.values.firstWhere((a) => a.name == v, orElse: () => ActivityLevel.light);
}

/// Body stats (synced). All optional until the user fills them in.
class BodyStats {
  const BodyStats({this.heightCm, this.weightKg, this.birthYear, this.sex, this.activity = ActivityLevel.light});

  final double? heightCm, weightKg;
  final int? birthYear;
  final Sex? sex;
  final ActivityLevel activity;

  bool get complete => heightCm != null && weightKg != null && birthYear != null && sex != null;

  int? ageAt(DateTime now) => birthYear == null ? null : now.year - birthYear!;

  /// Daily goals from Mifflin–St Jeor BMR × activity, with protein 1.6 g/kg,
  /// fat 25 % of energy, carbs the rest, fiber 14 g per 1,000 kcal, and
  /// water: the larger of 35 ml/kg and the EFSA adequate intake (men 2.5 L,
  /// women 2.0 L), plus extra for activity. Values are rounded to friendly
  /// steps. Null until [complete].
  Goals? suggestGoals({DateTime? now}) {
    if (!complete) return null;
    final w = weightKg!, h = heightCm!, age = ageAt(now ?? AppClock.now())!;
    final bmr = 10 * w + 6.25 * h - 5 * age + (sex == Sex.male ? 5 : -161);
    final kcal = _round(bmr * activity.factor, 50);
    final protein = _round(1.6 * w, 5);
    final fat = _round(kcal * 0.25 / 9, 5);
    final carbs = _round((kcal - protein * 4 - fat * 9) / 4, 5);
    return Goals(
      kcal: kcal,
      waterMl: _round(max(35 * w, sex == Sex.male ? 2500.0 : 2000.0) + activity.extraWaterMl, 250).round(),
      protein: protein,
      carbs: carbs,
      fiber: _round(kcal / 1000 * 14, 1),
      fat: fat,
    );
  }

  static double _round(double v, double step) => (v / step).round() * step;
}
