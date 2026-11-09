import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/currency.dart';
import '../../../data/finance_repo.dart';
import '../../../data/models.dart';
import '../../../state/data_providers.dart';
import '../../../state/settings_providers.dart';
import '../../theme/semantic.dart';
import '../../widgets/bars.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../widgets/switchers.dart';
import 'currency_picker.dart';
import 'export_sheet.dart';
import 'transaction_sheet.dart';

/// Finance (DESIGN.md §5, Finance.dc.html): month switcher + default currency,
/// Income / Expenses / Balance (per currency, no conversion), spending by
/// category (phone bars, Mac donut), transactions grouped by day.
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  /// "Add" (phone FAB / Mac header) and "Export" (phone ⋮ / Mac button).
  static Widget fab(BuildContext context) => FloatingActionButton.extended(
    onPressed: () => showTransactionSheet(context),
    icon: const Icon(Icons.add),
    label: const Text('Add'),
  );

  static List<Widget> actions(BuildContext context, WidgetRef ref) {
    final month = ref.read(financeMonthSelectedProvider);
    if (context.isWide && !context.isRoomy) {
      return [
        IconButton(
          tooltip: 'Export',
          onPressed: () => showExportSheet(context, month: month),
          icon: const Icon(Icons.download_outlined),
        ),
        IconButton.filledTonal(
          tooltip: 'Add transaction',
          onPressed: () => showTransactionSheet(context),
          icon: const Icon(Icons.add),
        ),
      ];
    }
    if (context.isWide) {
      return [
        OutlinedButton.icon(
          onPressed: () => showExportSheet(context, month: month),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Export'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: () => showTransactionSheet(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add transaction'),
        ),
      ];
    }
    return [
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (_) => showExportSheet(context, month: ref.read(financeMonthSelectedProvider)),
        itemBuilder: (_) => const [PopupMenuItem(value: 'export', child: Text('Export transactions'))],
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(financeMonthSelectedProvider);
    final currency = ref.watch(syncedSettingsProvider.select((s) => s.currency));
    final yyyyMm = DateFormat('yyyy-MM').format(month);
    final wide = context.isWide;
    return AsyncBody(
      value: ref.watch(financeMonthProvider(yyyyMm)),
      builder: (context, txs) {
        final s = MonthSummary(txs, currency);
        return PageBody(
          bottomPadding: 96,
          children: [
            MonthSwitcher(
              month: month,
              onChanged: ref.read(financeMonthSelectedProvider.notifier).select,
              trailing: ActionChip(
                tooltip: 'Default currency',
                label: Text('${Currency.of(currency).symbol} $currency'),
                avatar: const Icon(Icons.expand_more, size: 18),
                onPressed: () async {
                  final c = await pickCurrency(context, selected: currency);
                  if (c != null) await ref.read(syncedSettingsProvider.notifier).setCurrency(c);
                },
              ),
            ),
            _SummaryCard(summary: s),
            if (txs.isEmpty)
              EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No transactions in ${DateFormat('MMMM').format(month)}',
                message: 'Add income and expenses to see your balance and where the money goes.',
                action: FilledButton.icon(
                  onPressed: () => showTransactionSheet(context, day: _dayIn(month)),
                  icon: const Icon(Icons.add),
                  label: const Text('Add transaction'),
                ),
              )
            else ...[
              if (s.byCategory.isNotEmpty) (wide ? _DonutCard(summary: s) : _CategoryBars(summary: s)),
              for (final (day, list) in s.byDay) _DayCard(day: day, txs: list, currency: currency),
            ],
          ],
        );
      },
    );
  }

  /// Today when adding in the current month, else the 1st of [month].
  static DateTime _dayIn(DateTime month) {
    final now = DateTime.now();
    return now.year == month.year && now.month == month.month ? now : month;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final m = summary.main;
    final c = Currency.of(m.currency);
    final sem = context.sem;
    Widget cell(String label, String value, Color? color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.tt.bodySmall),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: context.tt.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              cell('Income', c.format(m.income), sem.income),
              const SizedBox(width: 12),
              cell('Expenses', c.format(m.expense), null),
              const SizedBox(width: 12),
              cell('Balance', c.format(m.balance), m.balance < 0 ? sem.expense : null),
            ],
          ),
          for (final o in summary.others)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${o.currency}: ${[if (o.income != 0) 'income ${Currency.of(o.currency).format(o.income)}', if (o.expense != 0) 'expenses ${Currency.of(o.currency).format(o.expense)}', 'balance ${Currency.of(o.currency).format(o.balance)}'].join(' · ')}',
                style: context.tt.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Phone: top 5 categories as bars + "others" line.
class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.summary});
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final cats = summary.categoriesSorted;
    final top = cats.take(5).toList();
    final rest = cats.skip(5).toList();
    final c = Currency.of(summary.defaultCurrency);
    final max = top.first.value.toDouble();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Spending by category', style: context.tt.titleMedium),
          const SizedBox(height: 8),
          for (final e in top)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(e.key, style: context.tt.bodyMedium)),
                      Text(c.format(e.value), style: context.tt.bodyMedium),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ProgressBar(value: e.value.toDouble(), goal: max, color: context.cs.primary),
                ],
              ),
            ),
          if (rest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+ ${rest.map((e) => e.key).join(', ')} · ${c.format(rest.fold(0, (a, e) => a + e.value))}',
                style: context.tt.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Mac: donut + legend (top 4 + "Other (n)").
class _DonutCard extends StatelessWidget {
  const _DonutCard({required this.summary});
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final palette = [context.cs.primary, sem.carbs, sem.fiber, sem.fat, context.cs.outline];
    final cats = summary.categoriesSorted;
    final slices = <(String, int)>[
      for (final e in cats.take(4)) (e.key, e.value),
      if (cats.length > 4) ('Other (${cats.length - 4})', cats.skip(4).fold(0, (a, e) => a + e.value)),
    ];
    final total = summary.main.expense;
    final c = Currency.of(summary.defaultCurrency);
    return AppCard(
      child: Row(
        children: [
          SizedBox.square(
            dimension: 160,
            child: CustomPaint(
              painter: _DonutPainter([for (final (i, s) in slices.indexed) (s.$2 / total, palette[i])]),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Spent', style: context.tt.bodySmall),
                    Text(c.format(total), style: context.tt.titleMedium),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: [
                for (final (i, (name, v)) in slices.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: palette[i], borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(name, style: context.tt.bodyMedium)),
                        Text(c.format(v), style: context.tt.bodyMedium),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${(v / total * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: context.tt.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);
  final List<(double fraction, Color color)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    var start = -math.pi / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final (f, color) in slices) {
      final sweep = 2 * math.pi * f;
      // Small gap between slices.
      canvas.drawArc(rect, start, math.max(0, sweep - 0.02), false, p..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices != slices;
}

/// One day: "Mon 2 Nov" + day net, then its transactions.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.txs, required this.currency});
  final String day, currency;
  final List<Tx> txs;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final inDefault = txs.where((t) => t.currency == currency);
    final net = inDefault.fold(0, (a, t) => a + t.signed);
    final c = Currency.of(currency);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(DateFormat('EEE d MMM').format(parseDay(day)), style: context.tt.titleSmall)),
              if (inDefault.isNotEmpty) Text(c.format(net, sign: true), style: context.tt.bodySmall),
            ],
          ),
          for (final t in txs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: context.cs.secondaryContainer,
                foregroundColor: context.cs.onSecondaryContainer,
                child: Text(t.category.characters.first.toUpperCase()),
              ),
              title: Text((t.note ?? '').isEmpty ? t.category : t.note!, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: (t.note ?? '').isEmpty ? null : Text(t.category),
              trailing: Text(
                Currency.of(t.currency).format(t.signed, sign: true),
                style: context.tt.titleSmall?.copyWith(color: t.kind == TxKind.income ? sem.income : null),
              ),
              onTap: () => showTransactionSheet(context, existing: t),
            ),
        ],
      ),
    );
  }
}
