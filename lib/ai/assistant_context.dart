import 'dart:convert';

import 'package:intl/intl.dart';

import '../data/currency.dart';
import '../data/db.dart';
import '../data/finance_repo.dart';
import '../data/food_repo.dart';
import '../data/models.dart';
import '../data/water_repo.dart';
import '../data/workout_repo.dart';
import '../app_clock.dart';

/// What the assistant may read (DESIGN.md §7.6), chosen per device on
/// You › AI models. Transaction notes are off by default.
enum AiScope {
  food('Food and water', 'Food log, My foods, meal plan, water', true),
  workouts('Workouts', 'Plans and this week’s sessions', true),
  finance('Money', 'This month’s totals and transactions', true),
  notes('Transaction notes', 'The notes you write on transactions', false);

  const AiScope(this.label, this.detail, this.defaultOn);
  final String label, detail;
  final bool defaultOn;

  static Set<AiScope> parse(List<String>? names) => names == null
      ? {
          for (final s in values)
            if (s.defaultOn) s,
        }
      : {
          for (final s in values)
            if (names.contains(s.name)) s,
        };
}

/// The data handed to the model with each conversation, and which sources
/// it came from (shown as a "Read …" chip on answers).
class AssistantContext {
  const AssistantContext(this.data, this.reads);

  /// Compact JSON. The app computes every number; the model only words it.
  final String data;
  final List<String> reads;

  static const empty = AssistantContext('{}', []);
}

String _r(double v) => v.round().toString();
String? _g(double? v) => v == null
    ? null
    : (v * 10).round() / 10 == v.roundToDouble()
    ? '${v.round()}'
    : v.toStringAsFixed(1);

/// Builds the context from the database for [scopes] as of [now].
Future<AssistantContext> buildAssistantContext(
  AppDb db, {
  required Set<AiScope> scopes,
  required Goals goals,
  required String currency,
  DateTime? now,
}) async {
  final t = now ?? AppClock.now();
  final today = dayKey(t);
  final data = <String, Object?>{'now': DateFormat('EEE d MMM yyyy, HH:mm').format(t)};
  final reads = <String>[];

  if (scopes.contains(AiScope.food)) {
    final food = FoodRepo(db), water = WaterRepo(db);
    final entries = await food.entries(FoodRepo.logs, today);
    final eaten = Nutrients.sum(entries.map((e) => e.totals));
    final workoutKcal = await WorkoutRepo(db).kcalAddedOn(today);
    data['goals'] = {
      'kcal': _r(goals.kcal),
      'protein_g': _r(goals.protein),
      'carbs_g': _r(goals.carbs),
      'fiber_g': _r(goals.fiber),
      'fat_g': _r(goals.fat),
      'water_ml': goals.waterMl,
    };
    data['today'] = {
      'eaten_kcal': _r(eaten.kcal),
      'kcal_left': _r(goals.kcal + workoutKcal - eaten.kcal),
      if (workoutKcal > 0) 'workout_kcal_added': _r(workoutKcal),
      'protein_g': ?_g(eaten.protein),
      'carbs_g': ?_g(eaten.carbs),
      'fiber_g': ?_g(eaten.fiber),
      'fat_g': ?_g(eaten.fat),
      'water_ml': await water.total(today),
      'meals': {
        for (final m in Meal.values)
          m.label: [
            for (final e in entries.where((e) => e.meal == m))
              {'food': e.name, 'g': _r(e.grams), 'kcal': _r(e.totals.kcal), 'protein_g': ?_g(e.totals.protein)},
          ],
      },
    };
    final week = await db.raw(
      'SELECT day, SUM(kcal * grams / 100.0) AS kcal FROM food_logs WHERE deleted = 0 AND day BETWEEN ? AND ? GROUP BY day',
      [dayKey(t.subtract(const Duration(days: 6))), today],
    );
    final waterWeek = await db.raw(
      'SELECT day, SUM(ml) AS ml FROM water_logs WHERE deleted = 0 AND day BETWEEN ? AND ? GROUP BY day',
      [dayKey(t.subtract(const Duration(days: 6))), today],
    );
    data['last_7_days'] = [
      for (var i = 6; i >= 0; i--)
        () {
          final d = dayKey(t.subtract(Duration(days: i)));
          final k = week.where((r) => r['day'] == d).firstOrNull?['kcal'] as num?;
          final w = waterWeek.where((r) => r['day'] == d).firstOrNull?['ml'] as num?;
          return {'day': d, 'kcal': k?.round() ?? 0, 'water_ml': w?.toInt() ?? 0};
        }(),
    ];
    final tomorrow = await food.entries(FoodRepo.plans, dayKey(t.add(const Duration(days: 1))));
    if (tomorrow.isNotEmpty) {
      data['plan_tomorrow'] = [
        for (final e in tomorrow) {'meal': e.meal.label, 'food': e.name, 'g': _r(e.grams), 'kcal': _r(e.totals.kcal)},
      ];
    }
    final mine = (await food.myFoods()).take(25);
    if (mine.isNotEmpty) {
      data['my_foods_per_100g'] = [
        for (final f in mine)
          {
            'food': f.name,
            'kcal': _r(f.per100g.kcal),
            'protein_g': ?_g(f.per100g.protein),
            if (f.servingG != null) 'serving_g': _r(f.servingG!),
          },
      ];
    }
    reads.addAll(['Today’s log', if (mine.isNotEmpty) 'My foods']);
  }

  if (scopes.contains(AiScope.workouts)) {
    final repo = WorkoutRepo(db);
    final monday = t.subtract(Duration(days: t.weekday - 1));
    final sessions = await repo.sessionsBetween(dayKey(monday), dayKey(monday.add(const Duration(days: 6))));
    final plans = await repo.plans();
    final activities = await repo.activitiesBetween(dayKey(monday), dayKey(monday.add(const Duration(days: 6))));
    data['workouts'] = {
      'plans': [
        for (final p in plans)
          {
            'name': p.name,
            'days': [for (final d in p.days.toList()..sort()) DateFormat('EEE').format(DateTime(2024, 1, d))],
            'exercises': p.exercises.length,
          },
      ],
      'this_week': [
        for (final s in sessions.where((s) => s.finished))
          {
            'day': s.day,
            'plan': s.planName,
            'minutes': s.endedAt!.difference(s.startedAt).inMinutes,
            'sets': s.sets.length,
            'volume_kg': _r(s.volume),
          },
      ],
      if (activities.isNotEmpty)
        'other_activities_this_week': [
          for (final a in activities)
            {
              'day': dayKey(a.start),
              'type': a.typeLabel,
              'app': ?a.source,
              if (a.km > 0) 'km': a.km.toStringAsFixed(1),
              'minutes': a.moving.inMinutes,
            },
        ],
    };
    reads.add('Workouts this week');
  }

  if (scopes.contains(AiScope.finance)) {
    final month = DateFormat('yyyy-MM').format(t);
    final s = MonthSummary(await FinanceRepo(db).month(month), currency);
    String money(int minor, String code) => Currency.of(code).format(minor);
    data['money_${DateFormat('MMMM_yyyy').format(t).toLowerCase()}'] = {
      for (final c in [s.main, ...s.others])
        c.currency: {
          'income': money(c.income, c.currency),
          'expenses': money(c.expense, c.currency),
          'balance': money(c.balance, c.currency),
          'transactions': c.count,
        },
      'expenses_by_category': {for (final e in s.categoriesSorted) e.key: money(e.value, currency)},
      'recent': [
        for (final tx in s.transactions.take(15))
          {
            'day': tx.day,
            tx.kind.name: money(tx.amountMinor, tx.currency),
            'category': tx.category,
            if (scopes.contains(AiScope.notes) && (tx.note ?? '').isNotEmpty) 'note': tx.note,
          },
      ],
    };
    reads.add('Transactions · ${DateFormat('MMM yyyy').format(t)}');
  }

  return AssistantContext(jsonEncode(data), reads);
}

/// The system prompt: the assistant's role, its rules, [ctx], and the
/// [earlier] turns of a chat being continued (fromUser, text), shortened.
String assistantInstructions(String assistantName, AssistantContext ctx, {List<(bool, String)> earlier = const []}) {
  String clip(String t) => t.length > 400 ? '${t.substring(0, 400)}…' : t;
  final recent = earlier.length > 8 ? earlier.sublist(earlier.length - 8) : earlier;
  return 'You are $assistantName, the assistant inside the user\'s personal app for food, water, workouts and money. '
      'Answer briefly and plainly, in a friendly tone. '
      'DATA below is the user\'s own data, computed by the app. Use its numbers exactly as given; do not recalculate '
      'totals. If something is not in DATA, say you can\'t see it rather than guessing. '
      'Amounts are already formatted with their currency. Food values are per entry unless marked per_100g. '
      'When suggesting food, prefer items from my_foods_per_100g and use their exact names.\n'
      'DATA: ${ctx.data}'
      '${recent.isEmpty ? '' : '\nEARLIER IN THIS CHAT:\n${recent.map((m) => '${m.$1 ? 'User' : 'You'}: ${clip(m.$2)}').join('\n')}'}';
}

/// Foods from [mine] that [text] names (whole words; a longer name wins over
/// one inside it), in the order the text mentions them, at most three, for
/// "Add to …" buttons under an answer.
List<FoodItem> foodsMentioned(String text, List<FoodItem> mine) {
  final lower = text.toLowerCase();
  final found = <(int, FoodItem)>[];
  final sorted = [...mine]..sort((a, b) => b.name.length.compareTo(a.name.length));
  for (final f in sorted) {
    final name = f.name.toLowerCase().trim();
    if (name.length < 3 || found.any((x) => x.$2.name.toLowerCase().contains(name))) continue;
    final at = RegExp('(^|[^a-z0-9])${RegExp.escape(name)}(\$|[^a-z0-9])').firstMatch(lower);
    if (at != null) found.add((at.start, f));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, f) in found.take(3)) f];
}
