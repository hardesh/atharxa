import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models.dart';
import '../../../services/reminder_plan.dart';
import '../../../state/reminders_controller.dart';
import '../../theme/semantic.dart';
import '../../widgets/layout.dart';

/// You › Reminders (DESIGN.md §5): meals, water, calorie check-ins — on this
/// device only. Turning a reminder off keeps its times.
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  static Future<ClockTime?> _pickTime(BuildContext context, ClockTime t) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: t ~/ 60, minute: t % 60),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(remindersProvider);
    final ctl = ref.read(remindersProvider.notifier);
    Widget timeButton(ClockTime t, ValueChanged<ClockTime> onPicked) => TextButton(
      onPressed: () async {
        final v = await _pickTime(context, t);
        if (v != null) onPicked(v);
      },
      child: Text(fmtClock(t), style: context.tt.titleMedium?.copyWith(color: context.cs.primary)),
    );

    return PageBody(
      children: [
        Text('On this device only', style: context.tt.bodySmall),
        _Card(
          title: 'Meals',
          subtitle: 'Skipped if that meal is already logged · shows kcal still to eat',
          children: [
            for (final meal in Meal.values)
              Row(
                children: [
                  Expanded(child: Text(meal.label, style: context.tt.bodyLarge)),
                  timeButton(s.mealTimes[meal]!, (t) => ctl.update(s.copyWith(mealTimes: {...s.mealTimes, meal: t}))),
                  Switch(
                    value: s.mealsOn[meal]!,
                    onChanged: (v) => ctl.update(s.copyWith(mealsOn: {...s.mealsOn, meal: v})),
                  ),
                ],
              ),
          ],
        ),
        _Card(
          title: 'Water',
          subtitle:
              'Every ${s.waterEveryH} h · ${fmtClock(s.waterStart)}–${fmtClock(s.waterEnd)} · stops once the goal is met',
          trailing: Switch(
            value: s.waterOn,
            onChanged: (v) => ctl.update(s.copyWith(waterOn: v)),
          ),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Every 1 h')),
                ButtonSegment(value: 2, label: Text('2 h')),
                ButtonSegment(value: 3, label: Text('3 h')),
              ],
              selected: {s.waterEveryH},
              onSelectionChanged: (v) => ctl.update(s.copyWith(waterEveryH: v.first)),
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('From', style: context.tt.bodyMedium),
                timeButton(s.waterStart, (t) => ctl.update(s.copyWith(waterStart: t))),
                Text('to', style: context.tt.bodyMedium),
                timeButton(s.waterEnd, (t) => ctl.update(s.copyWith(waterEnd: t))),
              ],
            ),
          ],
        ),
        _Card(
          title: 'Calorie check-in',
          subtitle: 'kcal left and protein so far',
          trailing: Switch(
            value: s.checkinOn,
            onChanged: (v) => ctl.update(s.copyWith(checkinOn: v)),
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final t in s.checkinTimes)
                  InputChip(
                    label: Text(fmtClock(t)),
                    onPressed: () async {
                      final v = await _pickTime(context, t);
                      if (v != null) {
                        ctl.update(s.copyWith(checkinTimes: [...s.checkinTimes.where((x) => x != t), v]..sort()));
                      }
                    },
                    onDeleted: s.checkinTimes.length > 1
                        ? () => ctl.update(s.copyWith(checkinTimes: s.checkinTimes.where((x) => x != t).toList()))
                        : null,
                  ),
                if (s.checkinTimes.length < 10)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add time'),
                    onPressed: () async {
                      final v = await _pickTime(context, 12 * 60);
                      if (v != null && !s.checkinTimes.contains(v)) {
                        ctl.update(s.copyWith(checkinTimes: [...s.checkinTimes, v]..sort()));
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: ctl.sendTest,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Send test notification'),
          ),
        ),
        Text(
          'Water reminders have +250 ml and Snooze buttons; meal reminders log your planned meal or open the '
          'food picker. Turning a reminder off keeps its times.',
          style: context.tt.bodySmall,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.tt.titleMedium),
                  if (subtitle != null) Text(subtitle!, style: context.tt.bodySmall),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}
