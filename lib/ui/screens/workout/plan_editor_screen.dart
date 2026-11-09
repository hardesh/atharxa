import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db.dart';
import '../../../data/workout_repo.dart';
import '../../../state/core_providers.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';

/// Edit plan (Workout.dc.html): name, repeat days, exercises with drag to
/// reorder, Add exercise, Save, Delete.
class PlanEditorScreen extends ConsumerStatefulWidget {
  const PlanEditorScreen({super.key, this.plan});
  final WorkoutPlan? plan;

  static Future<void> open(BuildContext context, {WorkoutPlan? plan}) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PlanEditorScreen(plan: plan)));

  @override
  ConsumerState<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends ConsumerState<PlanEditorScreen> {
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final Set<int> _days = {...?widget.plan?.days};

  /// Exercise rows being edited (existing ones keep their id).
  late final List<Map<String, Object?>> _exercises = [
    for (final e in widget.plan?.exercises ?? const <Exercise>[])
      AppDb.editable(e.row)
        ..remove('plan_id')
        ..remove('sort'),
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _editExercise([int? index]) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _ExerciseDialog(initial: index == null ? null : _exercises[index]),
    );
    if (result == null) return;
    setState(() => index == null ? _exercises.add(result) : _exercises[index] = result);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showMessage(context, 'Give the plan a name');
      return;
    }
    await WorkoutRepo(
      ref.read(dbProvider),
    ).savePlan(id: widget.plan?.id, name: _name.text, days: _days, exercises: _exercises);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final p = widget.plan!;
    final ok = await confirm(
      context,
      title: 'Delete ${p.name}?',
      message: 'The plan and its exercises are removed. Past workouts stay in your history.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await WorkoutRepo(ref.read(dbProvider)).deletePlan(p);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final minutes = WorkoutPlan(const {}, [
      for (final e in _exercises) Exercise({...e, 'plan_id': ''}),
    ]).estimatedMinutes;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plan == null ? 'New plan' : 'Edit plan'),
        actions: [
          if (widget.plan != null)
            IconButton(tooltip: 'Delete plan', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editExercise(),
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth + 2 * context.screenPad),
          child: ReorderableListView(
            padding: EdgeInsets.fromLTRB(context.screenPad, 8, context.screenPad, 96),
            onReorderItem: (from, to) => setState(() => _exercises.insert(to, _exercises.removeAt(from))),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Plan name', hintText: 'Lower body A'),
                ),
                const SizedBox(height: 16),
                Text('Repeats on', style: context.tt.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      Tooltip(
                        message: names[d - 1],
                        child: FilterChip(
                          label: Text(letters[d - 1]),
                          showCheckmark: false,
                          selected: _days.contains(d),
                          onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Exercises', style: context.tt.titleMedium)),
                    if (_exercises.length > 1) Text('Drag to reorder', style: context.tt.bodySmall),
                  ],
                ),
                if (_exercises.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No exercises yet — tap Add exercise.', style: context.tt.bodySmall),
                  ),
              ],
            ),
            footer: _exercises.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'About $minutes min · rest timers start automatically between sets',
                      style: context.tt.bodySmall,
                    ),
                  ),
            children: [
              for (final (i, e) in _exercises.indexed)
                ListTile(
                  key: ObjectKey(e),
                  contentPadding: const EdgeInsets.only(left: 4),
                  title: Text(e['name'] as String),
                  subtitle: Text(Exercise({...e, 'plan_id': ''}).summary),
                  onTap: () => _editExercise(i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Remove ${e['name']}',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _exercises.removeAt(i)),
                      ),
                      ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
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

/// Add / edit one exercise: name, sets, reps, kg, rest, YouTube links.
class _ExerciseDialog extends StatefulWidget {
  const _ExerciseDialog({this.initial});
  final Map<String, Object?>? initial;

  @override
  State<_ExerciseDialog> createState() => _ExerciseDialogState();
}

class _ExerciseDialogState extends State<_ExerciseDialog> {
  final _form = GlobalKey<FormState>();
  late final i = widget.initial;
  late final _name = TextEditingController(text: i?['name'] as String? ?? '');
  late final _sets = TextEditingController(text: '${i?['sets'] ?? 3}');
  late final _reps = TextEditingController(text: '${i?['reps'] ?? 10}');
  late final _kg = TextEditingController(text: i?['kg'] == null ? '' : '${i!['kg']}');
  late final _rest = TextEditingController(text: '${i?['rest_s'] ?? 90}');
  late final List<String> _videos = i?['videos'] == null
      ? []
      : (jsonDecode(i!['videos'] as String) as List).cast<String>();

  String? _int(String? v, int min, int max) {
    final x = int.tryParse(v ?? '');
    return x == null || x < min || x > max ? '$min–$max' : null;
  }

  Future<void> _addVideo() async {
    final url = await askText(
      context,
      title: 'Add a video',
      label: 'YouTube link',
      hint: 'https://youtu.be/…',
      keyboardType: TextInputType.url,
      confirmLabel: 'Add',
    );
    if (url != null && Uri.tryParse(url)?.hasScheme == true) setState(() => _videos.add(url));
  }

  void _done() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      if (i?['id'] != null) 'id': i!['id'],
      'name': _name.text.trim(),
      'sets': int.parse(_sets.text),
      'reps': int.parse(_reps.text),
      'kg': double.tryParse(_kg.text.replaceAll(',', '.')),
      'rest_s': int.parse(_rest.text),
      'videos': _videos.isEmpty ? null : jsonEncode(_videos),
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget num(
      TextEditingController c,
      String label, {
      String? suffix,
      String? Function(String?)? validator,
      bool decimal = false,
    }) => Expanded(
      child: TextFormField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))],
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        validator: validator,
      ),
    );
    return AlertDialog(
      title: Text(i == null ? 'Add exercise' : 'Edit exercise'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: i == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Exercise', hintText: 'Goblet squat'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  num(_sets, 'Sets', validator: (v) => _int(v, 1, 20)),
                  const SizedBox(width: 8),
                  num(_reps, 'Reps', validator: (v) => _int(v, 1, 200)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  num(_kg, 'Weight', suffix: 'kg', decimal: true),
                  const SizedBox(width: 8),
                  num(_rest, 'Rest', suffix: 's', validator: (v) => _int(v, 0, 900)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Leave weight empty for bodyweight.', style: context.tt.bodySmall),
              const SizedBox(height: 12),
              Text('Videos', style: context.tt.titleSmall),
              for (final (vi, v) in _videos.indexed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Remove video',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _videos.removeAt(vi)),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addVideo,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add YouTube link'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: Text(i == null ? 'Add' : 'Save')),
      ],
    );
  }
}
