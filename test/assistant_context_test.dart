import 'dart:convert';

import 'package:atharxa/ai/assistant_context.dart';
import 'package:atharxa/data/food_repo.dart';
import 'package:atharxa/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'finance_test.dart' show seedNovember;
import 'helpers.dart';
import 'nutrition_test.dart' as sample;

void main() {
  final now = DateTime(2026, 11, 9, 14, 30);

  test('scopes: notes off by default; stored names round-trip', () {
    expect(AiScope.parse(null), {AiScope.food, AiScope.workouts, AiScope.finance});
    expect(AiScope.parse(['finance', 'notes', 'bogus']), {AiScope.finance, AiScope.notes});
  });

  test('context carries app-computed numbers for the allowed scopes only', () async {
    final db = await openTestDb();
    final food = FoodRepo(db);
    final oats = await food.cache(sample.oats);
    await food.add(FoodRepo.logs, day: '2026-11-09', meal: Meal.breakfast, food: oats, grams: 60);
    await seedNovember(db);
    await db.save('transactions', {
      'day': '2026-11-08',
      'kind': 'expense',
      'amount_minor': 45000,
      'currency': 'INR',
      'category': 'Food',
      'note': 'dinner with Priya',
    });

    final ctx = await buildAssistantContext(
      db,
      scopes: {AiScope.food, AiScope.finance},
      goals: const Goals(),
      currency: 'INR',
      now: now,
    );
    final j = jsonDecode(ctx.data) as Map<String, Object?>;
    final today = j['today']! as Map<String, Object?>;
    expect(today['eaten_kcal'], '227'); // 60 g oats × 379 kcal/100 g
    expect(today['kcal_left'], '1973');
    expect((today['meals']! as Map)['Breakfast'], [
      {'food': 'Rolled oats', 'g': '60', 'kcal': '227', 'protein_g': '7.9'},
    ]);
    expect((j['last_7_days']! as List).last, {'day': '2026-11-09', 'kcal': 227, 'water_ml': 0});
    expect(j.containsKey('workouts'), isFalse);
    final money = j['money_november_2026']! as Map<String, Object?>;
    expect((money['INR']! as Map)['income'], '₹1,35,000');
    expect((money['USD']! as Map)['expenses'], isNotNull); // kept separate, not converted
    expect(ctx.data, isNot(contains('Priya'))); // notes need their own scope
    expect(ctx.reads, ['Today’s log', 'My foods', 'Transactions · Nov 2026']);

    final withNotes = await buildAssistantContext(
      db,
      scopes: {AiScope.finance, AiScope.notes},
      goals: const Goals(),
      currency: 'INR',
      now: now,
    );
    expect(withNotes.data, contains('dinner with Priya'));
    expect(jsonDecode(withNotes.data), isNot(contains('today')));
  });

  test('instructions embed the data', () {
    final p = assistantInstructions('Atharxa', const AssistantContext('{"x":1}', []));
    expect(p, startsWith('You are Atharxa'));
    expect(p, endsWith('DATA: {"x":1}'));
  });

  test('foods named in an answer become actions (whole words, in order, max 3)', () {
    final mine = [sample.dal, sample.chana, sample.paneer, sample.roti, sample.chai, sample.oats];
    final found = foodsMentioned('Try paneer bhurji with a roti, then roasted chana. Skip the masala chai.', mine);
    expect(found.map((f) => f.name), ['Paneer bhurji', 'Roti', 'Roasted chana']);
    expect(foodsMentioned('A rotisserie chicken', mine), isEmpty); // not "Roti"
  });

  test('a continued chat carries its earlier turns', () {
    final p = assistantInstructions(
      'Atharxa',
      AssistantContext.empty,
      earlier: [(true, 'Dinner idea?'), (false, 'Dal tadka.')],
    );
    expect(p, contains('EARLIER IN THIS CHAT:\nUser: Dinner idea?\nYou: Dal tadka.'));
  });
}
