import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models.dart';
import '../../../state/settings_providers.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../../app_clock.dart';

/// You › Body stats (synced): used by Goals › "Suggest from body stats".
class BodyStatsPage extends ConsumerStatefulWidget {
  const BodyStatsPage({super.key});

  @override
  ConsumerState<BodyStatsPage> createState() => _BodyStatsPageState();
}

class _BodyStatsPageState extends ConsumerState<BodyStatsPage> {
  final _form = GlobalKey<FormState>();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _birthYear = TextEditingController();
  Sex? _sex;
  ActivityLevel _activity = ActivityLevel.light;

  @override
  void initState() {
    super.initState();
    final b = ref.read(syncedSettingsProvider).body;
    String n(num? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : '$v');
    _height.text = n(b.heightCm);
    _weight.text = n(b.weightKg);
    _birthYear.text = n(b.birthYear);
    _sex = b.sex;
    _activity = b.activity;
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  String? Function(String?) _range(double min, double max, String unit) => (v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null; // optional
    final x = double.tryParse(t);
    if (x == null) return 'Enter a number';
    return x < min || x > max ? 'Between ${min.round()} and ${max.round()} $unit' : null;
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref
        .read(syncedSettingsProvider.notifier)
        .setBodyStats(
          BodyStats(
            heightCm: double.tryParse(_height.text.trim()),
            weightKg: double.tryParse(_weight.text.trim()),
            birthYear: int.tryParse(_birthYear.text.trim()),
            sex: _sex,
            activity: _activity,
          ),
        );
    if (mounted) showMessage(context, 'Body stats saved');
  }

  @override
  Widget build(BuildContext context) {
    final year = AppClock.now().year;
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return Form(
      key: _form,
      child: PageBody(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _height,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimal,
                  decoration: const InputDecoration(labelText: 'Height', suffixText: 'cm'),
                  validator: _range(100, 250, 'cm'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimal,
                  decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg'),
                  validator: _range(25, 300, 'kg'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _birthYear,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: const InputDecoration(labelText: 'Birth year'),
                  validator: _range(year - 110.0, year - 10.0, ''),
                ),
                const SizedBox(height: 16),
                Text('Sex (for the calorie formula)', style: context.tt.bodySmall),
                const SizedBox(height: 8),
                SegmentedButton<Sex>(
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: Sex.female, label: Text('Female')),
                    ButtonSegment(value: Sex.male, label: Text('Male')),
                  ],
                  selected: {?_sex},
                  onSelectionChanged: (v) => setState(() => _sex = v.firstOrNull),
                ),
              ],
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: RadioGroup<ActivityLevel>(
              groupValue: _activity,
              onChanged: (v) => setState(() => _activity = v ?? _activity),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('Activity level', style: context.tt.titleMedium),
                  ),
                  for (final a in ActivityLevel.values)
                    RadioListTile<ActivityLevel>(value: a, title: Text(a.label), subtitle: Text(a.description)),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
          Text('Body stats sync to your other devices and stay on them.', style: context.tt.bodySmall),
        ],
      ),
    );
  }
}
