import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db.dart';
import '../../data/food_repo.dart';
import '../../data/models.dart';
import '../app_scope.dart';
import '../format.dart';
import '../theme/semantic.dart';
import '../widgets/bars.dart';
import '../widgets/feedback.dart';
import '../widgets/layout.dart';
import '../widgets/meal_card.dart';
import '../widgets/switchers.dart';
import 'food/food_picker_screen.dart';
import 'food/portion_dialog.dart';

class _TodayData {
  _TodayData(this.entries, this.waterMl);
  final List<FoodEntry> entries;
  final int waterMl;
  Nutrients get totals => Nutrients.sum(entries.map((e) => e.totals));
}

/// Today — calorie tracking (DESIGN.md §5, board Main.dc.html).
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DateTime _date = DateTime.now();
  String get _day => dayKey(_date);

  Future<_TodayData> _load(AppDb db) async {
    final entries = await FoodRepo(db).entries(FoodRepo.logs, _day);
    final w = await db.raw('SELECT COALESCE(SUM(ml),0) AS ml FROM water_logs WHERE deleted = 0 AND day = ?', [_day]);
    return _TodayData(entries, (w.first['ml'] as num).toInt());
  }

  Future<void> _add(Meal meal) => FoodPickerScreen.open(context, table: FoodRepo.logs, date: _date, meal: meal);

  Future<void> _edit(FoodEntry e) async {
    final r = await PortionDialog.edit(context, e);
    if (r == null || !mounted) return;
    await FoodRepo(context.db).update(FoodRepo.logs, e, grams: r.grams, meal: r.meal);
  }

  Future<void> _remove(FoodEntry e) async {
    final repo = FoodRepo(context.db);
    await repo.remove(FoodRepo.logs, e.id);
    if (mounted) showUndo(context, 'Removed ${e.name}', () => repo.restore(FoodRepo.logs, e));
  }

  Future<void> _addWater(int ml) => context.db.save('water_logs', {
    'day': _day,
    'ml': ml,
    'logged_at': DateTime.now().millisecondsSinceEpoch,
    'source': 'today',
  });

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => _add(mealForNow()),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => _addWater(250),
      },
      child: ListenableBuilder(
        listenable: context.settings,
        builder: (context, _) => DbBuilder<_TodayData>(
          tables: const ['food_logs', 'water_logs'],
          deps: [_day],
          load: _load,
          builder: (context, d) {
            final goals = context.settings.goals;
            final summary = SummaryCard(totals: d.totals, goals: goals);
            final water = _WaterCard(ml: d.waterMl, goal: goals.waterMl, onAdd: _addWater);
            final cards = [
              for (final m in Meal.values)
                MealCard(
                  meal: m,
                  entries: d.entries.where((e) => e.meal == m).toList(),
                  onAdd: () => _add(m),
                  onEdit: _edit,
                  onRemove: _remove,
                ),
            ];
            return PageBody(
              children: [
                DateSwitcher(date: _date, onChanged: (v) => setState(() => _date = v)),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: summary),
                      SizedBox(width: context.cardGap),
                      Expanded(flex: 2, child: water),
                    ],
                  )
                else ...[
                  summary,
                  water,
                ],
                MealGrid(cards: cards, wide: wide, gap: context.cardGap),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.ml, required this.goal, required this.onAdd});

  final int ml, goal;
  final ValueChanged<int> onAdd;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: sem.waterContainer,
                  foregroundColor: sem.water,
                  child: const Icon(Icons.water_drop_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Water', style: context.tt.titleSmall)),
                          Text('${fmtInt(ml)} / ${fmtInt(goal)} ml', style: context.tt.bodyMedium),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ProgressBar(value: ml.toDouble(), goal: goal.toDouble(), color: sem.water),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in const [250, 500])
                    ActionChip(
                      avatar: Icon(Icons.add, size: 18, color: context.cs.onSurfaceVariant),
                      label: Text('$v ml'),
                      onPressed: () => onAdd(v),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
