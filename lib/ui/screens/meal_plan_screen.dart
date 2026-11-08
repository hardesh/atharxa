import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../data/food_repo.dart';
import '../../data/models.dart';
import '../app_scope.dart';
import '../format.dart';
import '../theme/semantic.dart';
import '../theme/text_scale.dart';
import '../widgets/bars.dart';
import '../widgets/feedback.dart';
import '../widgets/layout.dart';
import '../widgets/switchers.dart';
import 'food/food_picker_screen.dart';
import 'food/portion_dialog.dart';

/// Meal plan (DESIGN.md §5, MealPlan.dc.html). Defaults to tomorrow.
/// Phone rows are stacked (name + grams, then the nutrient line) with
/// swipe-left-to-remove; Mac shows a full table with a total row.
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _PlanData {
  _PlanData(this.plan, this.logged);
  final List<FoodEntry> plan;

  /// Entries already in that day's log (to detect logging a meal twice).
  final List<FoodEntry> logged;
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String get _day => dayKey(_date);

  Future<_PlanData> _load(AppDb db) async {
    final repo = FoodRepo(db);
    return _PlanData(await repo.entries(FoodRepo.plans, _day), await repo.entries(FoodRepo.logs, _day));
  }

  FoodRepo get _repo => FoodRepo(context.db);

  Future<void> _add(Meal m) => FoodPickerScreen.open(context, table: FoodRepo.plans, date: _date, meal: m);

  Future<void> _edit(FoodEntry e) async {
    final r = await PortionDialog.edit(context, e);
    if (r != null && mounted) await _repo.update(FoodRepo.plans, e, grams: r.grams, meal: r.meal);
  }

  Future<void> _remove(FoodEntry e) async {
    final repo = _repo;
    await repo.remove(FoodRepo.plans, e.id);
    if (mounted) showUndo(context, 'Removed ${e.name}', () => repo.restore(FoodRepo.plans, e));
  }

  /// True when every planned item already appears in that day's log.
  static bool _alreadyLogged(List<FoodEntry> items, List<FoodEntry> logged) =>
      items.isNotEmpty &&
      items.every((p) => logged.any((l) => l.meal == p.meal && l.name == p.name && (l.grams - p.grams).abs() < 1e-6));

  Future<void> _log(List<FoodEntry> items, List<FoodEntry> logged, {required String what}) async {
    if (items.isEmpty) return;
    if (_alreadyLogged(items, logged)) {
      final ok = await confirm(
        context,
        title: 'Log $what again?',
        message: 'These items are already in the log for ${relativeDay(_date)}. Logging again adds them a second time.',
        confirmLabel: 'Log again',
      );
      if (!ok || !mounted) return;
    }
    final repo = _repo;
    final n = await repo.copy(items, FoodRepo.logs, day: _day);
    if (mounted) showMessage(context, 'Logged $n ${n == 1 ? 'item' : 'items'} to ${relativeDay(_date)}');
  }

  Future<void> _copyFrom() async {
    final src = await showDatePicker(
      context: context,
      helpText: 'Copy plan from',
      initialDate: _date.subtract(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (src == null || !mounted) return;
    final repo = _repo;
    final items = await repo.entries(FoodRepo.plans, dayKey(src));
    if (!mounted) return;
    if (items.isEmpty) {
      showMessage(context, 'No plan on ${relativeDay(src)}');
      return;
    }
    final n = await repo.copy(items, FoodRepo.plans, day: _day);
    if (mounted) showMessage(context, 'Copied $n ${n == 1 ? 'item' : 'items'} from ${relativeDay(src)}');
  }

  Future<void> _clear(List<FoodEntry> plan) async {
    if (plan.isEmpty) return;
    final ok = await confirm(
      context,
      title: 'Clear plan?',
      message: 'Removes all ${plan.length} planned items for ${relativeDay(_date)}.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final repo = _repo;
    for (final e in plan) {
      await repo.remove(FoodRepo.plans, e.id);
    }
    if (mounted) {
      showUndo(context, 'Plan cleared', () async {
        for (final e in plan) {
          await repo.restore(FoodRepo.plans, e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.settings,
      builder: (context, _) => DbBuilder<_PlanData>(
        tables: const ['meal_plans', 'food_logs'],
        deps: [_day],
        load: _load,
        builder: (context, d) {
          final goals = context.settings.goals;
          final totals = Nutrients.sum(d.plan.map((e) => e.totals));
          final menu = PopupMenuButton<String>(
            tooltip: 'Plan options',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => switch (v) {
              'log' => _log(d.plan, d.logged, what: 'the whole day'),
              'copy' => _copyFrom(),
              _ => _clear(d.plan),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'log', enabled: d.plan.isNotEmpty, child: const Text('Log whole day')),
              const PopupMenuItem(value: 'copy', child: Text('Copy plan from another day…')),
              PopupMenuItem(value: 'clear', enabled: d.plan.isNotEmpty, child: const Text('Clear plan')),
            ],
          );
          final wide = context.isWide;
          return PageBody(
            children: [
              DateSwitcher(date: _date, onChanged: (v) => setState(() => _date = v)),
              _PlannedCard(totals: totals, goals: goals, menu: menu, wide: wide),
              for (final m in Meal.values)
                _PlanMealCard(
                  meal: m,
                  items: d.plan.where((e) => e.meal == m).toList(),
                  wide: wide,
                  onAdd: () => _add(m),
                  onLog: (items) => _log(items, d.logged, what: m.label),
                  onEdit: _edit,
                  onRemove: _remove,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PlannedCard extends StatelessWidget {
  const _PlannedCard({required this.totals, required this.goals, required this.menu, required this.wide});

  final Nutrients totals;
  final Goals goals;
  final Widget menu;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final diff = goals.kcal - totals.kcal;
    final s = context.sem;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(wide ? 'Planned total' : 'Planned', style: context.tt.bodySmall),
                      Text.rich(
                        TextSpan(
                          text: fmtInt(totals.kcal),
                          style: context.tt.headlineMedium,
                          children: [
                            TextSpan(
                              text: wide
                                  ? '  of ${fmtInt(goals.kcal)} kcal · ${fmtInt(diff.abs())} ${diff >= 0 ? 'under' : 'over'}'
                                  : ' / ${fmtInt(goals.kcal)} kcal',
                              style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                menu,
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: MacroBars(
                rows: [
                  MacroRow('Protein', totals.protein, goals.protein, s.protein),
                  MacroRow('Carbs', totals.carbs, goals.carbs, s.carbs),
                  MacroRow('Fiber', totals.fiber, goals.fiber, s.fiber),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "155 kcal · Protein 11.7 g · Carbs 16.5 g · Fiber 6.1 g" (plan rows omit fat, as in the board).
String _planLine(Nutrients n) =>
    '${fmtInt(n.kcal)} kcal · Protein ${fmtMacro(n.protein)} g · Carbs ${fmtMacro(n.carbs)} g · Fiber ${fmtMacro(n.fiber)} g';

class _PlanMealCard extends StatelessWidget {
  const _PlanMealCard({
    required this.meal,
    required this.items,
    required this.wide,
    required this.onAdd,
    required this.onLog,
    required this.onEdit,
    required this.onRemove,
  });

  final Meal meal;
  final List<FoodEntry> items;
  final bool wide;
  final VoidCallback onAdd;
  final ValueChanged<List<FoodEntry>> onLog;
  final ValueChanged<FoodEntry> onEdit, onRemove;

  @override
  Widget build(BuildContext context) {
    final total = Nutrients.sum(items.map((e) => e.totals));
    final stacked = !wide && (context.largeText || MediaQuery.sizeOf(context).width < 360);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(meal.label, style: context.tt.titleMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    items.isEmpty ? '' : '${fmtInt(total.kcal)} kcal',
                    style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant),
                  ),
                ),
                if (items.isNotEmpty) TextButton(onPressed: () => onLog(items), child: const Text('Log')),
                IconButton.filledTonal(tooltip: 'Add to ${meal.label}', onPressed: onAdd, icon: const Icon(Icons.add)),
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                child: Text('No components planned', style: context.tt.bodySmall),
              )
            else if (stacked)
              ..._stackedRows(context, total)
            else
              _table(context, total),
          ],
        ),
      ),
    );
  }

  List<Widget> _stackedRows(BuildContext context, Nutrients total) => [
    for (final e in items)
      Dismissible(
        key: ValueKey(e.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          color: context.cs.errorContainer,
          child: Icon(Icons.delete_outline, color: context.cs.onErrorContainer),
        ),
        onDismissed: (_) => onRemove(e),
        child: InkWell(
          onTap: () => onEdit(e),
          onLongPress: () => _rowMenu(context, e),
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.cs.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.name, style: context.tt.bodyMedium)),
                    Text('${fmtGrams(e.grams)} g', style: context.tt.bodyMedium),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_planLine(e.totals), style: context.tt.bodySmall),
              ],
            ),
          ),
        ),
      ),
    Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total · ${fmtInt(total.kcal)} kcal', style: context.tt.titleSmall),
          Text(
            'Protein ${fmtMacro(total.protein)} g · Carbs ${fmtMacro(total.carbs)} g · Fiber ${fmtMacro(total.fiber)} g',
            style: context.tt.bodySmall,
          ),
        ],
      ),
    ),
  ];

  Future<void> _rowMenu(BuildContext context, FoodEntry e) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit grams'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (v == 'edit') onEdit(e);
    if (v == 'remove') onRemove(e);
  }

  /// Component · g · kcal · Protein · Carbs · Fiber · ✕, plus a total row.
  Widget _table(BuildContext context, Nutrients total) {
    final head = context.tt.labelMedium?.copyWith(color: context.cs.onSurfaceVariant);
    final body = context.tt.bodyMedium;
    final bold = context.tt.titleSmall;
    final border = BorderSide(color: context.cs.outlineVariant);
    Widget cell(String t, TextStyle? s) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(t, textAlign: TextAlign.right, style: s),
    );
    TableRow row(List<Widget> cells, {bool top = true}) => TableRow(
      decoration: BoxDecoration(border: Border(top: top ? border : BorderSide.none)),
      children: cells,
    );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
        6: FixedColumnWidth(44),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        row(top: false, [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Component', style: head),
          ),
          cell('g', head),
          cell('kcal', head),
          cell('Protein', head),
          cell('Carbs', head),
          cell('Fiber', head),
          const SizedBox(),
        ]),
        for (final e in items)
          row([
            InkWell(
              onTap: () => onEdit(e),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(e.name, style: body, overflow: TextOverflow.ellipsis),
              ),
            ),
            cell(fmtGrams(e.grams), body),
            cell(fmtInt(e.totals.kcal), body),
            cell(fmtMacro(e.totals.protein), body),
            cell(fmtMacro(e.totals.carbs), body),
            cell(fmtMacro(e.totals.fiber), body),
            IconButton(
              tooltip: 'Remove ${e.name}',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => onRemove(e),
            ),
          ]),
        row([
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('Total', style: bold),
          ),
          const SizedBox(),
          cell(fmtInt(total.kcal), bold),
          cell(fmtMacro(total.protein), bold),
          cell(fmtMacro(total.carbs), bold),
          cell(fmtMacro(total.fiber), bold),
          const SizedBox(),
        ]),
      ],
    );
  }
}
