import 'package:atharxa/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suggested goals: Mifflin–St Jeor × activity with macro split', () {
    // Male, 178 cm, 75 kg, 30 years, moderate (×1.55):
    // BMR = 10·75 + 6.25·178 − 5·30 + 5 = 1,717.5 → ×1.55 = 2,662 → 2,650 kcal.
    const b = BodyStats(heightCm: 178, weightKg: 75, birthYear: 1996, sex: Sex.male, activity: ActivityLevel.moderate);
    final g = b.suggestGoals(now: DateTime(2026, 11, 9))!;
    expect(g.kcal, 2650);
    expect(g.protein, 120); // 1.6 g/kg
    expect(g.fat, 75); // 25 % of kcal / 9 = 73.6 → 75
    expect(g.carbs, 375); // (2650 − 480 − 675) / 4 = 373.75 → 375
    expect(g.fiber, 37); // 14 g / 1,000 kcal
    expect(g.waterMl, 2750); // 35 ml/kg = 2,625 → nearest 250
  });

  test('female formula and incomplete stats', () {
    const f = BodyStats(
      heightCm: 160,
      weightKg: 55,
      birthYear: 1996,
      sex: Sex.female,
      activity: ActivityLevel.sedentary,
    );
    // 550 + 1000 − 150 − 161 = 1,239 × 1.2 = 1,486.8 → 1,500
    expect(f.suggestGoals(now: DateTime(2026, 11, 9))!.kcal, 1500);
    expect(const BodyStats(heightCm: 160).suggestGoals(), isNull);
  });
}
