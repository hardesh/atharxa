import 'package:flutter/material.dart';

import '../../../data/food_repo.dart';
import '../../../data/models.dart';
import '../../app_scope.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';

/// Create / edit / delete a food in My foods (DESIGN.md §5, CustomFood.dc.html).
/// Values are per 100 g. Editing only affects future logs — past entries keep
/// their snapshot.
///
/// Returns the saved food when the user chose "Save and add to `meal`",
/// otherwise null.
class FoodEditorScreen extends StatefulWidget {
  const FoodEditorScreen({super.key, this.food, this.initialName, this.meal, this.inDialog = false});

  final FoodItem? food;
  final String? initialName;
  final Meal? meal;
  final bool inDialog;

  static Future<FoodItem?> open(BuildContext context, {FoodItem? food, String? initialName, Meal? meal}) {
    if (context.isWide) {
      return showDialog<FoodItem>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
            child: FoodEditorScreen(food: food, initialName: initialName, meal: meal, inDialog: true),
          ),
        ),
      );
    }
    return Navigator.push<FoodItem>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodEditorScreen(food: food, initialName: initialName, meal: meal),
      ),
    );
  }

  @override
  State<FoodEditorScreen> createState() => _FoodEditorScreenState();
}

class _FoodEditorScreenState extends State<FoodEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final FoodItem? f = widget.food;
  late final _name = TextEditingController(text: f?.name ?? widget.initialName ?? '');
  late final _brand = TextEditingController(text: f?.brand ?? '');
  late final _serving = TextEditingController(text: _v(f?.servingG));
  late final _kcal = TextEditingController(text: _v(f?.per100g.kcal));
  late final _protein = TextEditingController(text: _v(f?.per100g.protein));
  late final _carbs = TextEditingController(text: _v(f?.per100g.carbs));
  late final _fiber = TextEditingController(text: _v(f?.per100g.fiber));
  late final _fat = TextEditingController(text: _v(f?.per100g.fat));
  int _pastEntries = 0;

  static String _v(double? x) => x == null ? '' : fmtGrams(x).replaceAll(',', '');

  @override
  void initState() {
    super.initState();
    if (f?.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final n = await FoodRepo(context.db).pastEntryCount(f!.id!);
        if (mounted) setState(() => _pastEntries = n);
      });
    }
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', ''));

  Future<FoodItem?> _save() async {
    if (!_form.currentState!.validate()) return null;
    final item = FoodItem(
      id: f?.id,
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: f?.barcode,
      servingG: _num(_serving),
      source: f?.source ?? 'custom',
      per100g: Nutrients(
        kcal: _num(_kcal) ?? 0,
        protein: _num(_protein),
        carbs: _num(_carbs),
        fiber: _num(_fiber),
        fat: _num(_fat),
      ),
    );
    final id = await context.db.save('foods', item.toRow());
    return FoodItem.fromRow({...item.toRow(), 'id': id});
  }

  Future<void> _saveOnly() async {
    final saved = await _save();
    if (saved == null || !mounted) return;
    Navigator.pop(context);
    showMessage(context, widget.food == null ? 'Saved ${saved.name} to My foods' : 'Saved ${saved.name}');
  }

  Future<void> _saveAndAdd() async {
    final saved = await _save();
    if (saved != null && mounted) Navigator.pop(context, saved);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${f!.name}?',
      message: 'It is removed from My foods. Past log entries keep their values.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final db = context.db;
    await db.delete('foods', f!.id!);
    if (!mounted) return;
    Navigator.pop(context);
    showUndo(context, 'Deleted ${f!.name}', () => db.save('foods', f!.toRow()));
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? suffix,
    String? hint,
    bool required = false,
    bool number = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      textCapitalization: number ? TextCapitalization.none : TextCapitalization.sentences,
      decoration: InputDecoration(labelText: required ? '$label *' : label, suffixText: suffix, helperText: hint),
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return required ? 'Required' : null;
        if (!number) return null;
        final x = double.tryParse(t.replaceAll(',', ''));
        return x == null || x < 0 ? 'Enter a number' : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editing = f != null;
    final meal = widget.meal;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Discard', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(editing ? 'Edit food' : 'New food'),
        actions: [
          if (editing && f!.id != null)
            IconButton(tooltip: 'Delete food', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _saveOnly, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            widget.inDialog ? 24 : context.screenPad,
            8,
            widget.inDialog ? 24 : context.screenPad,
            32,
          ),
          children: [
            _field(_name, 'Name', required: true, number: false),
            _field(_brand, 'Brand / note', number: false),
            _field(_serving, 'Typical serving', suffix: 'g', hint: 'Adds a "1 serving" chip in the portion dialog'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Nutrition per 100 g', style: context.tt.titleSmall?.copyWith(color: context.cs.primary)),
            ),
            _field(_kcal, 'Energy', suffix: 'kcal', required: true),
            _field(_protein, 'Protein', suffix: 'g'),
            _field(_carbs, 'Carbs', suffix: 'g'),
            _field(_fiber, 'Fiber', suffix: 'g'),
            _field(_fat, 'Fat', suffix: 'g'),
            if (editing)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Changing values updates future logs only.'
                  '${_pastEntries > 0 ? ' $_pastEntries past log ${_pastEntries == 1 ? 'entry keeps' : 'entries keep'} the values they were logged with.' : ''}',
                  style: context.tt.bodySmall,
                ),
              ),
            if (!editing && meal != null) ...[
              FilledButton(onPressed: _saveAndAdd, child: Text('Save and add to ${meal.label}')),
              const SizedBox(height: 8),
              TextButton(onPressed: _saveOnly, child: const Text('Save to My foods only')),
            ],
          ],
        ),
      ),
    );
  }
}
