import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/food_repo.dart';
import '../../data/models.dart';
import '../../state/core_providers.dart';
import '../../state/data_providers.dart';
import '../../state/settings_providers.dart';
import '../format.dart';
import '../theme/semantic.dart';
import '../widgets/bars.dart';
import '../widgets/feedback.dart';
import '../widgets/layout.dart';
import '../widgets/meal_card.dart';
import '../widgets/switchers.dart';
import '../widgets/water_entries.dart';
import 'food/food_picker_screen.dart';
import 'food/portion_dialog.dart';

/// Overview — calorie tracking + water for a day (DESIGN.md §5 "Today", board Main.dc.html).
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDayProvider);
    final goals = ref.watch(goalsProvider);
    final wide = context.isWide;

    Future<void> add(Meal meal) => FoodPickerScreen.open(context, table: FoodRepo.logs, date: date, meal: meal);
    Future<void> addWater(int ml) => addWaterWithUndo(context, date, ml, 'today');

    Future<void> edit(FoodEntry e) async {
      final r = await PortionDialog.edit(context, e);
      if (r == null) return;
      await FoodRepo(ref.read(dbProvider)).update(FoodRepo.logs, e, grams: r.grams, meal: r.meal);
    }

    Future<void> remove(FoodEntry e) async {
      final repo = FoodRepo(ref.read(dbProvider));
      await repo.remove(FoodRepo.logs, e.id);
      if (context.mounted) showUndo(context, 'Removed ${e.name}', () => repo.restore(FoodRepo.logs, e));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => add(mealForNow()),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => addWater(250),
      },
      child: AsyncBody(
        value: ref.watch(overviewProvider(dayKey(date))),
        builder: (context, d) {
          final summary = SummaryCard(totals: Nutrients.sum(d.entries.map((e) => e.totals)), goals: goals);
          final water = _WaterCard(
            ml: d.waterMl,
            goal: goals.waterMl,
            onAdd: addWater,
            onOpen: () => showWaterEntriesSheet(context, date),
          );
          final cards = [
            for (final m in Meal.values)
              MealCard(
                meal: m,
                entries: d.entries.where((e) => e.meal == m).toList(),
                onAdd: () => add(m),
                onEdit: edit,
                onRemove: remove,
              ),
          ];
          return PageBody(
            children: [
              DateSwitcher(date: date, onChanged: ref.read(selectedDayProvider.notifier).select),
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
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.ml, required this.goal, required this.onAdd, required this.onOpen});

  final int ml, goal;
  final ValueChanged<int> onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    return Card(
      child: InkWell(
        onTap: onOpen,
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
      ),
    );
  }
}
