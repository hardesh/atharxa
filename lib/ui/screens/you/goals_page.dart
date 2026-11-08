import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models.dart';
import '../../../state/settings_providers.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';

/// You › Goals (synced): Calories, Water, Protein, Carbs, Fiber, Fat.
/// "Suggest from body stats" fills the form; nothing is saved until Save.
class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key, this.onOpenBodyStats});

  /// Opens You › Body stats (when the suggestion needs them).
  final VoidCallback? onOpenBodyStats;

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;

  static const _fields = [
    ('kcal', 'Calories', 'kcal', 800.0, 8000.0),
    ('water', 'Water', 'ml', 500.0, 10000.0),
    ('protein', 'Protein', 'g', 10.0, 500.0),
    ('carbs', 'Carbs', 'g', 10.0, 1000.0),
    ('fiber', 'Fiber', 'g', 5.0, 150.0),
    ('fat', 'Fat', 'g', 10.0, 400.0),
  ];

  @override
  void initState() {
    super.initState();
    _c = {for (final f in _fields) f.$1: TextEditingController()};
    _fill(ref.read(goalsProvider));
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Goals g) {
    String v(num x) => x.round().toString();
    _c['kcal']!.text = v(g.kcal);
    _c['water']!.text = v(g.waterMl);
    _c['protein']!.text = v(g.protein);
    _c['carbs']!.text = v(g.carbs);
    _c['fiber']!.text = v(g.fiber);
    _c['fat']!.text = v(g.fat);
  }

  double _v(String k) => double.parse(_c[k]!.text.trim());

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(syncedSettingsProvider.notifier)
        .setGoals(
          Goals(
            kcal: _v('kcal'),
            waterMl: _v('water').round(),
            protein: _v('protein'),
            carbs: _v('carbs'),
            fiber: _v('fiber'),
            fat: _v('fat'),
          ),
        );
    if (mounted) showMessage(context, 'Goals saved');
  }

  void _suggest() {
    final suggestion = ref.read(syncedSettingsProvider).body.suggestGoals();
    if (suggestion == null) {
      showMessage(context, 'Add your height, weight, birth year and sex in Body stats first.');
      widget.onOpenBodyStats?.call();
      return;
    }
    setState(() => _fill(suggestion));
    showMessage(context, 'Suggested goals filled in — review and Save');
  }

  @override
  Widget build(BuildContext context) {
    final body = ref.watch(syncedSettingsProvider.select((s) => s.body));
    return Form(
      key: _form,
      child: PageBody(
        children: [
          AppCard(
            child: Column(
              children: [
                for (final (key, label, unit, min, max) in _fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextFormField(
                      controller: _c[key],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: label, suffixText: unit),
                      validator: (v) {
                        final x = double.tryParse(v?.trim() ?? '');
                        if (x == null) return 'Enter a number';
                        if (x < min || x > max) return 'Between ${fmtInt(min)} and ${fmtInt(max)} $unit';
                        return null;
                      },
                    ),
                  ),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: _suggest,
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: const Text('Suggest from body stats'),
                ),
                const SizedBox(height: 6),
                Text(
                  body.complete
                      ? 'Uses your height, weight, age and activity level (${body.activity.label.toLowerCase()}).'
                      : 'Uses height, weight and activity level from Body stats.',
                  style: context.tt.bodySmall,
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
          Text('Goals sync to your other devices.', style: context.tt.bodySmall),
        ],
      ),
    );
  }
}
