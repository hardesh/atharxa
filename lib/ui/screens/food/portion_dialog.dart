import 'package:flutter/material.dart';

import '../../../data/models.dart';
import '../../format.dart';
import '../../theme/semantic.dart';

class PortionResult {
  PortionResult(this.grams, this.meal);
  final double grams;
  final Meal meal;
}

/// Portion dialog (DESIGN.md §5, FoodPicker.dc.html): grams field (focused),
/// serving / 100 g chips, per-100 g line, live preview, meal selector.
class PortionDialog extends StatefulWidget {
  const PortionDialog({
    super.key,
    required this.name,
    required this.subtitle,
    required this.per100,
    required this.meal,
    this.servingG,
    this.initialGrams,
    this.confirmVerb = 'Add to',
    this.editing = false,
  });

  final String name, subtitle;
  final Nutrients per100;
  final Meal meal;
  final double? servingG, initialGrams;
  final String confirmVerb;
  final bool editing;

  static Future<PortionResult?> add(BuildContext context, FoodItem f, Meal meal, {String verb = 'Add to'}) =>
      showDialog<PortionResult>(
        context: context,
        builder: (_) => PortionDialog(
          name: f.name,
          subtitle: [if (f.brand != null && f.brand!.isNotEmpty) f.brand!, f.sourceLabel].join(' · '),
          per100: f.per100g,
          meal: meal,
          servingG: f.servingG,
          confirmVerb: verb,
        ),
      );

  static Future<PortionResult?> edit(BuildContext context, FoodEntry e) => showDialog<PortionResult>(
    context: context,
    builder: (_) => PortionDialog(
      name: e.name,
      subtitle: e.brand ?? 'Logged entry',
      per100: e.per100,
      meal: e.meal,
      initialGrams: e.grams,
      editing: true,
    ),
  );

  @override
  State<PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<PortionDialog> {
  late final _c = TextEditingController(
    text: fmtGrams(widget.initialGrams ?? widget.servingG ?? 100).replaceAll(',', ''),
  );
  late Meal _meal = widget.meal;

  double get _g => double.tryParse(_c.text.trim()) ?? 0;

  void _set(double g) => setState(() => _c.text = fmtGrams(g).replaceAll(',', ''));

  void _submit() {
    if (_g > 0) Navigator.pop(context, PortionResult(_g, _meal));
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.per100.forGrams(_g);
    Widget cell(String v, String label) => Expanded(
      child: Column(
        children: [
          Text(v, style: context.tt.titleMedium, maxLines: 1),
          Text(label, style: context.tt.bodySmall),
        ],
      ),
    );
    return AlertDialog(
      title: Text(widget.name),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subtitle, style: context.tt.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Grams', suffixText: 'g'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.servingG != null)
                  ActionChip(
                    label: Text('1 serving (${fmtGrams(widget.servingG!)} g)'),
                    onPressed: () => _set(widget.servingG!),
                  ),
                ActionChip(label: const Text('100 g'), onPressed: () => _set(100)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Per 100 g: ${nutrientLine(widget.per100)}', style: context.tt.bodySmall),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(color: context.cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  cell(fmtInt(n.kcal), 'kcal'),
                  cell(fmtMacro(n.protein), 'Protein'),
                  cell(fmtMacro(n.carbs), 'Carbs'),
                  cell(fmtMacro(n.fiber), 'Fiber'),
                  cell(fmtMacro(n.fat), 'Fat'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Meal', style: context.tt.bodyMedium),
                const SizedBox(width: 12),
                MenuAnchor(
                  menuChildren: [
                    for (final m in Meal.values)
                      MenuItemButton(onPressed: () => setState(() => _meal = m), child: Text(m.label)),
                  ],
                  builder: (context, ctl, _) => InputChip(
                    selected: true,
                    showCheckmark: false,
                    label: Text(_meal.label),
                    deleteIcon: const Icon(Icons.arrow_drop_down),
                    onDeleted: () => ctl.isOpen ? ctl.close() : ctl.open(),
                    onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _g > 0 ? _submit : null,
          child: Text(widget.editing ? 'Save' : '${widget.confirmVerb} ${_meal.label}'),
        ),
      ],
    );
  }
}
