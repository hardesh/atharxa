import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/currency.dart';
import '../../../data/finance_repo.dart';
import '../../../data/models.dart';
import '../../../state/core_providers.dart';
import '../../../state/data_providers.dart';
import '../../../state/settings_providers.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import 'currency_picker.dart';

/// Add or edit a transaction (DESIGN.md §5 Finance): Expense/Income, amount
/// + currency, category chips (+ custom), date, note. Saving shows Undo.
Future<void> showTransactionSheet(BuildContext context, {Tx? existing, DateTime? day}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _TransactionSheet(existing: existing, day: day),
);

class _TransactionSheet extends ConsumerStatefulWidget {
  const _TransactionSheet({this.existing, this.day});
  final Tx? existing;
  final DateTime? day;

  @override
  ConsumerState<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends ConsumerState<_TransactionSheet> {
  late TxKind _kind = widget.existing?.kind ?? TxKind.expense;
  late String _currency = widget.existing?.currency ?? ref.read(syncedSettingsProvider).currency;
  late String? _category = widget.existing?.category;
  late DateTime _date = widget.existing == null ? (widget.day ?? DateTime.now()) : parseDay(widget.existing!.day);
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _amount.text = Currency.of(e.currency).plain(e.amountMinor).replaceFirst(RegExp(r'\.0+$'), '');
      _note.text = e.note ?? '';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Currency get _cur => Currency.of(_currency);
  int? get _minor => _cur.parseMinor(_amount.text);
  bool get _valid => _minor != null && _category != null;

  Future<void> _newCategory() async {
    final name = await askText(
      context,
      title: 'New category',
      label: 'Name',
      capitalization: TextCapitalization.words,
      confirmLabel: 'Add',
    );
    if (name == null || name.isEmpty) return;
    final saved = await FinanceRepo(ref.read(dbProvider)).addCategory(name, _kind);
    setState(() => _category = saved);
  }

  Future<void> _save() async {
    final minor = _minor;
    if (minor == null || _category == null) return;
    final repo = FinanceRepo(ref.read(dbProvider));
    final before = widget.existing;
    final id = await repo.save({
      'id': ?before?.id,
      'day': dayKey(_date),
      'kind': _kind.name,
      'amount_minor': minor,
      'currency': _currency,
      'category': _category,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    });
    if (!mounted) return;
    showUndo(
      context,
      '${_kind.label} saved · ${_cur.format(minor)} $_category',
      () => before == null ? repo.remove(id) : repo.restore(before),
    );
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final t = widget.existing!;
    final repo = FinanceRepo(ref.read(dbProvider));
    await repo.remove(t.id);
    if (!mounted) return;
    showUndo(context, 'Deleted ${Currency.of(t.currency).format(t.amountMinor)} ${t.category}', () => repo.restore(t));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider(_kind)).value ?? const <String>[];
    final editing = widget.existing != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(editing ? 'Edit transaction' : 'New transaction', style: context.tt.titleLarge)),
                  if (editing)
                    IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<TxKind>(
                segments: const [
                  ButtonSegment(value: TxKind.expense, label: Text('Expense'), icon: Icon(Icons.remove)),
                  ButtonSegment(value: TxKind.income, label: Text('Income'), icon: Icon(Icons.add)),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() {
                  _kind = v.first;
                  _category = null;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                autofocus: !editing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: context.tt.headlineSmall,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: TextButton(
                    onPressed: () async {
                      final c = await pickCurrency(context, selected: _currency);
                      if (c != null) setState(() => _currency = c);
                    },
                    child: Text('${_cur.symbol} ${_cur.code}'),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text('Category', style: context.tt.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in cats)
                    ChoiceChip(
                      label: Text(c),
                      selected: c == _category,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                    onPressed: _newCategory,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(relativeDay(_date)),
                subtitle: const Text('Date'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _valid ? _save : null, child: Text('Save ${_kind.label.toLowerCase()}')),
            ],
          ),
        ),
      ),
    );
  }
}
