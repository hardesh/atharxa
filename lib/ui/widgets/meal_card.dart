import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../format.dart';
import '../theme/semantic.dart';
import '../../app_clock.dart';

/// Meal card (DESIGN.md §4): name + kcal subtotal + tonal "+"; rows
/// "Rolled oats · 60 g" with the nutrient line; tap = edit grams; ✕ = remove.
/// Null callbacks make the card read-only (a locked or future day).
class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.meal,
    required this.entries,
    this.onAdd,
    this.onEdit,
    this.onRemove,
    this.headerAction,
    this.emptyText = 'Nothing logged yet',
  });

  final Meal meal;
  final List<FoodEntry> entries;
  final VoidCallback? onAdd;
  final ValueChanged<FoodEntry>? onEdit;
  final ValueChanged<FoodEntry>? onRemove;
  final Widget? headerAction;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final kcal = entries.fold<double>(0, (a, e) => a + e.totals.kcal);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(meal.label, style: context.tt.titleMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entries.isEmpty ? '' : '${fmtInt(kcal)} kcal',
                    style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant),
                  ),
                ),
                ?headerAction,
                if (onAdd != null)
                  IconButton.filledTonal(
                    tooltip: 'Add food to ${meal.label}',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                  )
                else
                  const SizedBox(height: 48),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: Text(emptyText, style: context.tt.bodySmall),
              ),
            for (final e in entries)
              EntryRow(
                entry: e,
                onTap: onEdit == null ? null : () => onEdit!(e),
                onRemove: onRemove == null ? null : () => onRemove!(e),
              ),
          ],
        ),
      ),
    );
  }
}

/// One food entry: "Name · 60 g" + nutrient line (wraps to two lines if needed).
class EntryRow extends StatelessWidget {
  const EntryRow({super.key, required this.entry, this.onTap, this.onRemove});

  final FoodEntry entry;
  final VoidCallback? onTap, onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Edit grams of ${entry.name}',
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.name} · ${fmtGrams(entry.grams)} g', style: context.tt.bodyMedium),
                      const SizedBox(height: 2),
                      Text(nutrientLine(entry.totals), style: context.tt.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            IconButton(tooltip: 'Remove ${entry.name}', onPressed: onRemove, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

/// Lays out four meal cards: one column on phones, a 2-column grid when wide.
class MealGrid extends StatelessWidget {
  const MealGrid({super.key, required this.cards, required this.wide, required this.gap});

  final List<Widget> cards;
  final bool wide;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) SizedBox(height: gap), cards[i]],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) SizedBox(height: gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[i]),
              SizedBox(width: gap),
              Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
            ],
          ),
        ],
      ],
    );
  }
}

/// Meal suggested by the time of day (⌘N, notifications).
Meal mealForNow([DateTime? now]) {
  final h = (now ?? AppClock.now()).hour;
  if (h < 11) return Meal.breakfast;
  if (h < 16) return Meal.lunch;
  if (h < 19) return Meal.snacks;
  return Meal.dinner;
}
