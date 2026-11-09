import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' show UrlOpener;

import '../../../data/exercise_tips.dart';
import '../../../data/workout_repo.dart';
import '../../../state/core_providers.dart';
import '../../../state/settings_providers.dart';
import '../../../state/strava_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../widgets/youtube_video.dart';

/// Live workout (WorkoutSession.dc.html): timer, exercise n of m, set k of n,
/// reps/kg steppers, Complete set (auto rest timer), set chips, form tips,
/// videos, up next. Sets are saved as they're completed, so a session can be
/// resumed after the app closes.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, required this.plan, required this.sessionId});
  final WorkoutPlan plan;
  final String sessionId;

  static Future<void> open(BuildContext context, {required WorkoutPlan plan, required String sessionId}) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(plan: plan, sessionId: sessionId),
        ),
      );

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  WorkoutSession? _session;
  Timer? _tick;
  int _restLeft = 0;
  int _reps = 0;
  double _kg = 0;
  ExerciseTips? _tips;
  String? _tipsFor;

  WorkoutRepo get _repo => WorkoutRepo(ref.read(dbProvider));
  List<Exercise> get _exercises => widget.plan.exercises;

  @override
  void initState() {
    super.initState();
    _reload();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _restLeft = _restLeft > 0 ? _restLeft - 1 : 0);
      if (_restLeft == 1) HapticFeedback.mediumImpact();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final s = await _repo.session(widget.sessionId);
    if (!mounted || s == null) return;
    setState(() => _session = s);
    _resetSteppers();
  }

  int _doneFor(Exercise e) => _session?.sets.where((s) => s.row['exercise_id'] == e.id).length ?? 0;

  /// Index of the exercise in progress (first with sets left), or null when all done.
  int? get _current {
    for (final (i, e) in _exercises.indexed) {
      if (_doneFor(e) < e.sets) return i;
    }
    return null;
  }

  int get _setsDone => _session?.sets.length ?? 0;

  void _resetSteppers() {
    final i = _current;
    if (i == null) return;
    final e = _exercises[i];
    _reps = e.reps;
    _kg = e.kg ?? 0;
    if (_tipsFor != e.name) {
      _tipsFor = e.name;
      ExerciseTips.forExercise(e.name).then((t) {
        if (mounted) setState(() => _tips = t);
      });
    }
  }

  Future<void> _completeSet() async {
    final i = _current;
    if (i == null) return;
    final e = _exercises[i];
    await _repo.logSet(
      widget.sessionId,
      e,
      setNo: _doneFor(e) + 1,
      reps: _reps,
      kg: e.kg == null && _kg == 0 ? null : _kg,
    );
    await _reload();
    if (!mounted) return;
    if (_current == null) {
      await _finish();
    } else {
      setState(() => _restLeft = e.restS);
    }
  }

  Future<void> _finish() async {
    final s = _session;
    if (s == null) return;
    if (s.sets.isEmpty) {
      final discard = await confirm(
        context,
        title: 'End without any sets?',
        message: 'Nothing was logged, so the workout will be discarded.',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard || !mounted) return;
      await _repo.discardSession(s.id);
      if (mounted) Navigator.pop(context);
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CompleteScreen(session: s, plan: widget.plan),
      ),
    );
  }

  /// The YouTube video shown for [e]: the one picked, else its first link.
  String? _playing;
  String? _playingFor(Exercise e) {
    final ids = e.videos.map(youTubeId).whereType<String>().toList();
    return ids.contains(_playing) ? _playing : ids.firstOrNull;
  }

  Future<void> _openVideo(String url) async {
    try {
      if (UrlOpener.instance.isSupported() && UrlOpener.instance.open(url).success) return;
    } catch (_) {}
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) showMessage(context, 'Link copied — paste it in your browser or YouTube');
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final i = _current;
    final totalSets = widget.plan.totalSets;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plan.name),
        actions: [
          TextButton(onPressed: s == null ? null : _finish, child: const Text('End workout')),
          const SizedBox(width: 8),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : i == null
          ? Center(
              child: FilledButton(onPressed: _finish, child: const Text('Finish workout')),
            )
          : _body(context, _exercises[i], i, totalSets),
    );
  }

  Widget _body(BuildContext context, Exercise e, int i, int totalSets) {
    final done = _doneFor(e);
    final next = i + 1 < _exercises.length ? _exercises[i + 1] : null;
    final logged = _session!.sets.where((x) => x.row['exercise_id'] == e.id).toList();
    return PageBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmtDuration(DateTime.now().difference(_session!.startedAt)),
              style: context.tt.displaySmall?.copyWith(color: context.cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Exercise ${i + 1} of ${_exercises.length} · $_setsDone of $totalSets sets done',
                style: context.tt.bodySmall,
              ),
            ),
          ],
        ),
        LinearProgressIndicator(
          value: totalSets == 0 ? 0 : _setsDone / totalSets,
          borderRadius: BorderRadius.circular(4),
        ),
        Text(e.name, style: context.tt.headlineMedium),
        Text(
          'Set ${done + 1} of ${e.sets} · target ${e.reps} reps · ${e.kg == null ? 'bodyweight' : '${fmtGrams(e.kg!)} kg'}',
          style: context.tt.bodyMedium,
        ),
        if (_restLeft > 0)
          Card(
            color: context.cs.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Rest ${fmtDuration(Duration(seconds: _restLeft))}', style: context.tt.titleLarge),
                  ),
                  TextButton(onPressed: () => setState(() => _restLeft += 30), child: const Text('+30 s')),
                  TextButton(onPressed: () => setState(() => _restLeft = 0), child: const Text('Skip')),
                ],
              ),
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Stepper(
                    label: 'Reps',
                    value: '$_reps',
                    onMinus: _reps > 1 ? () => setState(() => _reps--) : null,
                    onPlus: () => setState(() => _reps++),
                  ),
                  _Stepper(
                    label: 'kg',
                    value: fmtGrams(_kg),
                    onMinus: _kg >= 2.5 ? () => setState(() => _kg -= 2.5) : null,
                    onPlus: () => setState(() => _kg += 2.5),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _completeSet,
                icon: const Icon(Icons.check),
                label: const Text('Complete set'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var n = 1; n <= e.sets; n++)
                    Chip(
                      backgroundColor: n == done + 1 ? context.cs.secondaryContainer : null,
                      label: Text(switch (n) {
                        _ when n <= logged.length =>
                          'Set $n · ${logged[n - 1].reps} × ${logged[n - 1].kg == null ? 'BW' : '${fmtGrams(logged[n - 1].kg!)} kg'} ✓',
                        _ when n == done + 1 => 'Set $n · now',
                        _ => 'Set $n',
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_tips != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Form tips', style: context.tt.titleMedium),
                const SizedBox(height: 6),
                for (final t in _tips!.tips) Text('•  $t', style: context.tt.bodyMedium),
                if (_tips!.mistake != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Common mistake: ${_tips!.mistake}',
                    style: context.tt.bodySmall?.copyWith(color: context.cs.error),
                  ),
                ],
              ],
            ),
          ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Videos', style: context.tt.titleMedium),
              if (e.videos.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('No videos yet — add YouTube links in the plan.', style: context.tt.bodySmall),
                ),
              if (_playingFor(e) case final id?) ...[const SizedBox(height: 8), YouTubeVideo(videoId: id)],
              if (e.videos.length > 1 || (e.videos.isNotEmpty && _playingFor(e) == null))
                for (final v in e.videos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(youTubeId(v) == _playingFor(e) ? Icons.play_circle : Icons.play_circle_outline),
                    title: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
                    // YouTube links play here; anything else opens outside the app.
                    onTap: () => youTubeId(v) == null ? _openVideo(v) : setState(() => _playing = youTubeId(v)),
                  ),
            ],
          ),
        ),
        if (next != null) Text('Up next: ${next.name} · ${next.summary}', style: context.tt.bodyMedium),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onMinus, required this.onPlus});
  final String label, value;
  final VoidCallback? onMinus, onPlus;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: context.tt.bodySmall),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(tooltip: 'Less $label', onPressed: onMinus, icon: const Icon(Icons.remove)),
          SizedBox(
            width: 64,
            child: Text(value, textAlign: TextAlign.center, style: context.tt.headlineSmall),
          ),
          IconButton.filledTonal(tooltip: 'More $label', onPressed: onPlus, icon: const Icon(Icons.add)),
        ],
      ),
    ],
  );
}

/// Workout complete: duration, sets, volume, energy estimate, feel, notes,
/// Add kcal to Today (off by default), Save.
class CompleteScreen extends ConsumerStatefulWidget {
  const CompleteScreen({super.key, required this.session, required this.plan});
  final WorkoutSession session;
  final WorkoutPlan plan;

  @override
  ConsumerState<CompleteScreen> createState() => _CompleteScreenState();
}

class _CompleteScreenState extends ConsumerState<CompleteScreen> {
  String? _feel;
  bool _addKcal = false;

  /// Starts from the Connected services default; only when connected.
  late bool _upload = ref.read(stravaProvider).account?.uploadByDefault ?? false;
  final _notes = TextEditingController();
  late final DateTime _end = DateTime.now();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final duration = _end.difference(s.startedAt);
    final kcal = estimateKcal(duration: duration, bodyWeightKg: ref.watch(syncedSettingsProvider).body.weightKg);
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.tt.bodySmall),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: context.tt.titleLarge),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Workout complete'), automaticallyImplyLeading: false),
      body: PageBody(
        children: [
          Text(widget.plan.name, style: context.tt.headlineSmall),
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    stat('Duration', fmtDuration(duration)),
                    stat('Sets', '${s.sets.length} / ${widget.plan.totalSets}'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    stat('Volume', '${fmtInt(s.volume)} kg'),
                    stat('Energy (estimate)', '≈ ${fmtInt(kcal)} kcal'),
                  ],
                ),
              ],
            ),
          ),
          Text('How did it feel?', style: context.tt.titleMedium),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'easy', label: Text('Easy')),
              ButtonSegment(value: 'good', label: Text('Good')),
              ButtonSegment(value: 'hard', label: Text('Hard')),
            ],
            selected: {?_feel},
            onSelectionChanged: (v) => setState(() => _feel = v.firstOrNull),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'e.g. RDL felt easy — go heavier next time',
            ),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('Add ${fmtInt(kcal)} kcal to Today'),
                  subtitle: const Text('Raises today’s calorie budget'),
                  value: _addKcal,
                  onChanged: (v) => setState(() => _addKcal = v),
                ),
                if (ref.watch(stravaProvider.select((st) => st.connected)))
                  SwitchListTile(
                    title: const Text('Upload to Strava'),
                    subtitle: const Text('As a Weight Training activity'),
                    value: _upload,
                    onChanged: (v) => setState(() => _upload = v),
                  )
                else
                  ListTile(
                    title: const Text('Upload to Strava'),
                    subtitle: const Text('Connect Strava in You › Connected services'),
                    enabled: false,
                  ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () async {
              final strava = ref.read(stravaProvider.notifier);
              final upload = _upload && ref.read(stravaProvider).connected;
              final messenger = ScaffoldMessenger.of(context);
              await WorkoutRepo(
                ref.read(dbProvider),
              ).finishSession(s, feel: _feel, notes: _notes.text, kcal: kcal, addKcalToToday: _addKcal);
              if (context.mounted) Navigator.pop(context);
              if (upload) {
                final finished = WorkoutSession({
                  ...s.row,
                  'ended_at': _end.millisecondsSinceEpoch,
                  'notes': _notes.text.trim(),
                }, s.sets);
                final error = await strava.upload(finished);
                messenger.showSnackBar(SnackBar(content: Text(error ?? 'Uploaded to Strava')));
              }
            },
            child: const Text('Save workout'),
          ),
        ],
      ),
    );
  }
}
