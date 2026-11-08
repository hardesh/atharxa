import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/data_providers.dart';
import '../../state/settings_providers.dart';
import '../format.dart';
import '../theme/semantic.dart';
import '../widgets/water_entries.dart';
import '../widgets/layout.dart';
import '../widgets/switchers.dart';

/// Water (DESIGN.md §5, Water.dc.html): ring, quick-add +250/+500/+750/Custom,
/// last-7-days chart with a goal line, and the day's entries with their source.
class WaterScreen extends ConsumerWidget {
  const WaterScreen({super.key});

  Future<void> _custom(BuildContext context, DateTime date) async {
    final c = TextEditingController();
    final ml = await showDialog<int>(
      context: context,
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, int.tryParse(c.text.trim()));
        return AlertDialog(
          title: const Text('Add water'),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount', suffixText: 'ml'),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Add')),
          ],
        );
      },
    );
    if (ml != null && ml > 0 && ml <= 5000 && context.mounted) await addWaterWithUndo(context, date, ml, 'water');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDayProvider);
    final day = dayKey(date);
    final goal = ref.watch(goalsProvider).waterMl;
    final wide = context.isWide;
    final entries = ref.watch(waterEntriesProvider(day));
    final week = ref.watch(waterWeekProvider(day));
    return AsyncBody(
      value: entries,
      builder: (context, rows) {
        final total = rows.fold<int>(0, (a, r) => a + (r['ml'] as num).toInt());
        final ring = _RingCard(
          total: total,
          goal: goal,
          onAdd: (ml) => addWaterWithUndo(context, date, ml, 'water'),
          onCustom: () => _custom(context, date),
        );
        final chart = _WeekCard(date: date, week: week.value ?? const {}, goal: goal, wide: wide);
        return PageBody(
          children: [
            DateSwitcher(date: date, onChanged: ref.read(selectedDayProvider.notifier).select),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ring),
                  SizedBox(width: context.cardGap),
                  Expanded(child: chart),
                ],
              )
            else ...[
              ring,
              chart,
            ],
            _EntriesCard(entries: rows, date: date, wide: wide),
          ],
        );
      },
    );
  }
}

class _RingCard extends StatelessWidget {
  const _RingCard({required this.total, required this.goal, required this.onAdd, required this.onCustom});

  final int total, goal;
  final ValueChanged<int> onAdd;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final left = goal - total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox.square(
              dimension: 184,
              child: CustomPaint(
                painter: _RingPainter(value: goal <= 0 ? 0 : total / goal, color: sem.water, track: sem.waterContainer),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(fmtInt(total), style: context.tt.headlineMedium),
                      Text('of ${fmtInt(goal)} ml', style: context.tt.bodyMedium),
                      const SizedBox(height: 2),
                      Text(left > 0 ? '${fmtInt(left)} to go' : 'Goal met', style: context.tt.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final ml in const [250, 500, 750])
                  FilledButton.tonal(onPressed: () => onAdd(ml), child: Text('+$ml ml')),
                OutlinedButton(onPressed: onCustom, child: const Text('Custom…')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 2 * math.pi, false, p..color = track);
    final v = value.clamp(0.0, 1.0);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.date, required this.week, required this.goal, required this.wide});

  final DateTime date;
  final Map<String, int> week;
  final int goal;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final days = [for (var i = 6; i >= 0; i--) date.subtract(Duration(days: i))];
    final values = [for (final d in days) week[dayKey(d)] ?? 0];
    final met = values.where((v) => goal > 0 && v >= goal).length;
    final maxV = math.max(goal * 7 / 6, values.fold<int>(0, math.max).toDouble());
    final chartH = wide ? 180.0 : 140.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 7 days', style: wide ? context.tt.titleMedium : context.tt.titleSmall),
            Text('Goal met $met of 7${wide ? ' · dashed line = ${fmtInt(goal)} ml' : ''}', style: context.tt.bodySmall),
            const SizedBox(height: 16),
            SizedBox(
              height: chartH,
              child: CustomPaint(
                foregroundPainter: _GoalLinePainter(
                  fraction: maxV <= 0 ? 0 : goal / maxV,
                  color: context.cs.onSurfaceVariant,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Tooltip(
                          message: '${DateFormat('EEE d MMM').format(days[i])}: ${fmtInt(values[i])} ml',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Container(
                              height: math.max(3, chartH * values[i] / maxV),
                              decoration: BoxDecoration(
                                color: goal > 0 && values[i] >= goal ? sem.water : sem.waterContainer,
                                borderRadius: BorderRadius.circular(6),
                                border: i == 6 ? Border.all(color: sem.water, width: 2) : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      children: [
                        if (wide) Text(fmtInt(values[i]), style: context.tt.bodySmall),
                        Text(
                          '${goal > 0 && values[i] >= goal ? '✓ ' : ''}${DateFormat('E').format(days[i]).substring(0, 1)}',
                          style: context.tt.bodySmall,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalLinePainter extends CustomPainter {
  _GoalLinePainter({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (fraction <= 0 || fraction > 1) return;
    final y = size.height * (1 - fraction);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_GoalLinePainter old) => old.fraction != fraction || old.color != color;
}

class _EntriesCard extends StatelessWidget {
  const _EntriesCard({required this.entries, required this.date, required this.wide});

  final List<Map<String, Object?>> entries;
  final DateTime date;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isToday ? 'Today’s entries' : 'Entries', style: wide ? context.tt.titleMedium : context.tt.titleSmall),
            if (entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text('Tap an entry to change the amount or time.', style: context.tt.bodySmall),
              ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No water logged yet', style: context.tt.bodySmall),
              ),
            for (final r in entries) WaterEntryTile(row: r),
          ],
        ),
      ),
    );
  }
}
