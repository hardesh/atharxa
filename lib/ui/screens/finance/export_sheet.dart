import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/finance_repo.dart';
import '../../../data/models.dart';
import '../../../services/file_saver.dart';
import '../../../services/transactions_export.dart';
import '../../../state/core_providers.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';

/// Export transactions (DESIGN.md §5 Finance › Export, Export.dc.html).
Future<void> showExportSheet(BuildContext context, {required DateTime month}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ExportSheet(month: month),
);

enum _Range { month, last3, year, custom }

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.month});
  final DateTime month;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  var _options = const ExportOptions();
  var _range = _Range.month;
  DateTimeRange? _custom;
  List<Tx>? _txs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _bounds {
    final m = widget.month;
    final endOfMonth = DateTime(m.year, m.month + 1, 0);
    return switch (_range) {
      _Range.month => (DateTime(m.year, m.month), endOfMonth),
      _Range.last3 => (DateTime(m.year, m.month - 2), endOfMonth),
      _Range.year => (DateTime(m.year), DateTime(m.year, 12, 31)),
      _Range.custom => (_custom?.start ?? m, _custom?.end ?? endOfMonth),
    };
  }

  Future<void> _load() async {
    final (from, to) = _bounds;
    final txs = await FinanceRepo(ref.read(dbProvider)).between(dayKey(from), dayKey(to));
    if (mounted) setState(() => _txs = txs);
  }

  void _set({_Range? range, ExportOptions? options}) {
    setState(() {
      _range = range ?? _range;
      _options = options ?? _options;
    });
    if (range != null) _load();
  }

  Future<void> _save() async {
    final txs = _txs;
    if (txs == null) return;
    final export = TransactionsExport(txs, _options);
    final (from, to) = _bounds;
    final name = TransactionsExport.fileName(dayKey(from), dayKey(to), _options.format);
    setState(() => _saving = true);
    try {
      final where = await saveExportedFile(name, export.build());
      if (!mounted) return;
      if (where != null) {
        showMessage(context, 'Saved ${export.rows.length} transactions to $where');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txs = _txs;
    final count = txs == null ? null : TransactionsExport(txs, _options).rows.length;
    final (from, to) = _bounds;
    final name = TransactionsExport.fileName(dayKey(from), dayKey(to), _options.format);
    final xlsx = _options.format == ExportFormat.xlsx;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Export transactions', style: context.tt.titleLarge),
              const SizedBox(height: 16),
              Text('Format', style: context.tt.bodySmall),
              const SizedBox(height: 8),
              SegmentedButton<ExportFormat>(
                segments: const [
                  ButtonSegment(value: ExportFormat.csv, label: Text('CSV')),
                  ButtonSegment(value: ExportFormat.xlsx, label: Text('Excel')),
                ],
                selected: {_options.format},
                onSelectionChanged: (v) => _set(options: _options.copyWith(format: v.first)),
              ),
              const SizedBox(height: 16),
              Text('Range', style: context.tt.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (r, label) in [
                    (_Range.month, fmtMonth(widget.month)),
                    (_Range.last3, 'Last 3 months'),
                    (_Range.year, 'This year'),
                    (
                      _Range.custom,
                      _custom == null ? 'Custom…' : '${fmtDayShort(_custom!.start)} – ${fmtDayShort(_custom!.end)}',
                    ),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _range == r,
                      onSelected: (_) async {
                        if (r == _Range.custom) {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDateRange: _custom,
                          );
                          if (picked == null) return;
                          _custom = picked;
                        }
                        _set(range: r);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Include', style: context.tt.bodySmall),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expenses'),
                value: _options.expenses,
                onChanged: (v) => _set(options: _options.copyWith(expenses: v)),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Income'),
                value: _options.income,
                onChanged: (v) => _set(options: _options.copyWith(income: v)),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notes'),
                value: _options.notes,
                onChanged: (v) => _set(options: _options.copyWith(notes: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add “By category” and “Summary” sheets'),
                subtitle: const Text('Excel only'),
                value: _options.extraSheets && xlsx,
                onChanged: xlsx ? (v) => _set(options: _options.copyWith(extraSheets: v)) : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expenses as negative amounts'),
                subtitle: const Text('Handy for SUM() in spreadsheets'),
                value: _options.negativeExpenses,
                onChanged: (v) => _set(options: _options.copyWith(negativeExpenses: v)),
              ),
              const SizedBox(height: 8),
              Text(count == null ? 'Counting…' : '$count transactions · file: $name', style: context.tt.bodySmall),
              if (_options.format == ExportFormat.csv)
                Text('UTF-8 with BOM so Excel shows ₹ correctly', style: context.tt.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: count == null || count == 0 || _saving ? null : _save,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(Platform.isMacOS ? 'Save…' : 'Save to Downloads'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
