import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models.dart';
import '../../../data/workout_repo.dart';
import '../../../state/core_providers.dart';
import '../../../state/data_providers.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../widgets/tag.dart';
import 'plan_editor_screen.dart';
import 'plan_sharing.dart';
import 'session_screen.dart';

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Mon · Wed · Fri" (or "No fixed days").
String daysLabel(Set<int> days) =>
    days.isEmpty ? 'No fixed days' : (days.toList()..sort()).map((d) => _weekdayShort[d - 1]).join(' · ');

enum _DayStatus { done, today, planned, rest }

/// Workout (DESIGN.md §5, Workout.dc.html): week strip, today's plan with
/// Start (or Resume), week stats, plans, recent sessions.
class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref, WorkoutPlan p) async {
    final id = await WorkoutRepo(ref.read(dbProvider)).startSession(p);
    if (context.mounted) await SessionScreen.open(context, plan: p, sessionId: id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    return AsyncBody(
      value: ref.watch(workoutProvider(dayKey(today))),
      builder: (context, d) {
        final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
        final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
        final doneDays = {
          for (final s in d.week)
            if (s.finished) s.day,
        };
        _DayStatus status(DateTime day) {
          if (doneDays.contains(dayKey(day))) return _DayStatus.done;
          if (DateUtils.isSameDay(day, today)) return _DayStatus.today;
          return d.plans.any((p) => p.repeatsOn(day)) ? _DayStatus.planned : _DayStatus.rest;
        }

        final planned = week.where((day) => d.plans.any((p) => p.repeatsOn(day))).length;
        final todayPlan = d.plans.where((p) => p.repeatsOn(today)).firstOrNull;
        final finished = d.week.where((s) => s.finished).toList();
        if (d.plans.isEmpty && d.week.isEmpty) {
          return EmptyState(
            icon: Icons.fitness_center,
            title: 'No workout plans yet',
            message:
                'Create a plan with your exercises and the days it repeats on. Rest timers and set tracking come with it.',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => PlanEditorScreen.open(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Create a plan'),
                ),
                OutlinedButton.icon(
                  onPressed: () => showImportPlans(context),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Import a plan'),
                ),
              ],
            ),
          );
        }
        return PageBody(
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'This week · ${DateFormat('d').format(week.first)}–${DateFormat('d MMM').format(week.last)}',
                          style: context.tt.titleMedium,
                        ),
                      ),
                      if (planned > 0) Text('${doneDays.length} of $planned done', style: context.tt.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final day in week)
                        Expanded(
                          child: _DayDot(day: day, status: status(day)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _TodayCard(
              active: d.active,
              plan: todayPlan,
              plans: d.plans,
              onStart: (p) => _start(context, ref, p),
              onResume: (s) {
                final p = d.plans.where((p) => p.id == s.planId).firstOrNull;
                if (p == null) return;
                SessionScreen.open(context, plan: p, sessionId: s.id);
              },
            ),
            AppCard(
              child: Row(
                children: [
                  _Stat(label: 'Sessions', value: '${doneDays.length} / ${planned == 0 ? '–' : planned}'),
                  _Stat(label: 'Volume', value: '${fmtInt(finished.fold(0.0, (a, s) => a + s.volume))} kg'),
                  _Stat(
                    label: 'Time',
                    value: '${finished.fold(0, (a, s) => a + s.endedAt!.difference(s.startedAt).inMinutes)} min',
                  ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Plans', style: context.tt.titleMedium)),
                      IconButton(
                        tooltip: 'Import plans',
                        onPressed: () => showImportPlans(context),
                        icon: const Icon(Icons.download_outlined),
                      ),
                      if (d.plans.isNotEmpty)
                        IconButton(
                          tooltip: 'Share all plans',
                          onPressed: () => sharePlans(context, d.plans),
                          icon: const Icon(Icons.ios_share),
                        ),
                      TextButton.icon(
                        onPressed: () => PlanEditorScreen.open(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New plan'),
                      ),
                    ],
                  ),
                  for (final p in d.plans)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text(
                        '${daysLabel(p.days)} · ${p.exercises.length} exercises · about ${p.estimatedMinutes} min',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => PlanEditorScreen.open(context, plan: p),
                    ),
                ],
              ),
            ),
            if (finished.isNotEmpty)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('This week', style: context.tt.titleMedium),
                    for (final s in finished)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(s.planName),
                        subtitle: Text(
                          '${DateFormat('EEE d MMM').format(s.startedAt)} · '
                          '${s.endedAt!.difference(s.startedAt).inMinutes} min · ${s.sets.length} sets · '
                          '${fmtInt(s.volume)} kg',
                        ),
                      ),
                  ],
                ),
              ),
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.directions_run),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Runs and rides from Strava, and uploading workouts, arrive in a later update.',
                      style: context.tt.bodySmall,
                    ),
                  ),
                  const Tag('soon', small: true),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day, required this.status});
  final DateTime day;
  final _DayStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (bg, fg, icon) = switch (status) {
      _DayStatus.done => (cs.primary, cs.onPrimary, Icons.check),
      _DayStatus.today => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.circle),
      _DayStatus.planned => (cs.surfaceContainerHigh, cs.onSurfaceVariant, Icons.circle),
      _DayStatus.rest => (Colors.transparent, cs.outline, Icons.remove),
    };
    return Semantics(
      label: '${DateFormat('EEEE').format(day)}: ${status.name}',
      child: Column(
        children: [
          Text(DateFormat('E').format(day).substring(0, 1), style: context.tt.bodySmall),
          const SizedBox(height: 6),
          CircleAvatar(
            radius: 16,
            backgroundColor: bg,
            foregroundColor: fg,
            child: Icon(icon, size: status == _DayStatus.done || status == _DayStatus.rest ? 18 : 8),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.tt.bodySmall),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: context.tt.titleMedium),
        ),
      ],
    ),
  );
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.active,
    required this.plan,
    required this.plans,
    required this.onStart,
    required this.onResume,
  });

  final WorkoutSession? active;
  final WorkoutPlan? plan;
  final List<WorkoutPlan> plans;
  final ValueChanged<WorkoutPlan> onStart;
  final ValueChanged<WorkoutSession> onResume;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final a = active;
    final p = plan;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today · ${DateFormat('EEE d MMM').format(DateTime.now())}',
              style: context.tt.bodySmall?.copyWith(color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 4),
            if (a != null) ...[
              Text(
                'Workout in progress · ${a.planName}',
                style: context.tt.titleLarge?.copyWith(color: cs.onPrimaryContainer),
              ),
              Text('${a.sets.length} sets done', style: context.tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => onResume(a),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume'),
              ),
            ] else if (p != null) ...[
              Text(p.name, style: context.tt.titleLarge?.copyWith(color: cs.onPrimaryContainer)),
              Text(
                '${p.exercises.length} exercises · ${p.totalSets} sets · about ${p.estimatedMinutes} min',
                style: context.tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: p.exercises.isEmpty ? null : () => onStart(p),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start workout'),
              ),
            ] else ...[
              Text('Rest day', style: context.tt.titleLarge?.copyWith(color: cs.onPrimaryContainer)),
              if (plans.any((p) => p.exercises.isNotEmpty)) ...[
                const SizedBox(height: 8),
                MenuAnchor(
                  menuChildren: [
                    for (final p in plans.where((p) => p.exercises.isNotEmpty))
                      MenuItemButton(onPressed: () => onStart(p), child: Text(p.name)),
                  ],
                  builder: (context, ctl, _) => OutlinedButton.icon(
                    onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start a workout anyway'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
