import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../format.dart';
import '../theme/semantic.dart';
import '../theme/text_scale.dart';

/// Rounded progress bar. Over-goal shows full in [overColor] when given.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    required this.goal,
    required this.color,
    this.track,
    this.height = 8,
    this.overColor,
  });

  final double value, goal, height;
  final Color color;
  final Color? track, overColor;

  @override
  Widget build(BuildContext context) {
    final over = goal > 0 && value > goal;
    final pct = goal <= 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track ?? context.cs.surfaceContainerHigh),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: over && overColor != null ? overColor : color,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MacroRow {
  const MacroRow(this.label, this.value, this.goal, this.color);
  final String label;
  final double? value;
  final double goal;
  final Color color;
}

/// Protein / Carbs / Fiber / Fat rows: "label · bar · 65.9 / 120 g".
/// Narrow screens or large text use a stacked variant (label + value on one
/// line, bar underneath) so numbers never truncate.
class MacroBars extends StatelessWidget {
  const MacroBars({super.key, required this.rows, this.track, this.textColor});

  final List<MacroRow> rows;
  final Color? track, textColor;

  static List<MacroRow> forTotals(BuildContext context, Nutrients t, Goals g) {
    final s = context.sem;
    return [
      MacroRow('Protein', t.protein, g.protein, s.protein),
      MacroRow('Carbs', t.carbs, g.carbs, s.carbs),
      MacroRow('Fiber', t.fiber, g.fiber, s.fiber),
      MacroRow('Fat', t.fat, g.fat, s.fat),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final label = context.tt.titleSmall?.copyWith(color: textColor);
    final val = context.tt.bodyMedium?.copyWith(color: textColor);
    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < 330 || context.largeText;
        return Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(r.label, style: label)),
                              Text('${fmtMacro(r.value)} / ${fmtInt(r.goal)} g', style: val),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ProgressBar(value: r.value ?? 0, goal: r.goal, color: r.color, track: track),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(width: 64, child: Text(r.label, style: label)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ProgressBar(value: r.value ?? 0, goal: r.goal, color: r.color, track: track),
                          ),
                          const SizedBox(width: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 104),
                            child: Text(
                              '${fmtMacro(r.value)} / ${fmtInt(r.goal)} g',
                              style: val,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
              ),
          ],
        );
      },
    );
  }
}

/// Today / Meal plan summary: "702 kcal left", 12 dp calorie bar, divider,
/// four macro bars, on primaryContainer. Over goal → "120 kcal over", error bar.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.totals, required this.goals, this.trailing, this.planned = false});

  final Nutrients totals;
  final Goals goals;
  final Widget? trailing;

  /// Meal plan wording: "planned" instead of "eaten".
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, sem = context.sem;
    final on = cs.onPrimaryContainer;
    final left = goals.kcal - totals.kcal;
    final over = left < 0;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtInt(left.abs()), style: context.tt.displaySmall?.copyWith(color: on)),
                      Text(over ? 'kcal over' : 'kcal left', style: context.tt.bodyMedium?.copyWith(color: on)),
                    ],
                  ),
                ),
                Text(
                  '${fmtInt(totals.kcal)} ${planned ? 'planned' : 'eaten'}\nof ${fmtInt(goals.kcal)} goal',
                  textAlign: TextAlign.right,
                  style: context.tt.bodyMedium?.copyWith(color: on),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            ProgressBar(
              value: totals.kcal,
              goal: goals.kcal,
              color: cs.primary,
              overColor: cs.error,
              track: sem.track,
              height: 12,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(color: on.withValues(alpha: .18), height: 1),
            ),
            MacroBars(rows: MacroBars.forTotals(context, totals, goals), track: sem.track, textColor: on),
          ],
        ),
      ),
    );
  }
}
