import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/water_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/core_providers.dart';
import '../../state/data_providers.dart';
import '../format.dart';
import '../theme/semantic.dart';
import 'feedback.dart';

/// Where an entry was added. Stored keys stay stable ('today' = the Overview card).
const waterSourceLabels = {
  'today': 'from Overview',
  'water': 'from Water',
  'notification': 'from a reminder',
  'mac': 'on Mac',
};

const _sourceIcons = {
  'today': Icons.dashboard_outlined,
  'water': Icons.water_drop_outlined,
  'notification': Icons.notifications_none,
  'mac': Icons.laptop_mac,
};

DateTime _at(Map<String, Object?> r) => DateTime.fromMillisecondsSinceEpoch((r['logged_at'] as num).toInt());

/// Adds water and shows an Undo snackbar, so a mistaken tap is one tap to fix.
Future<void> addWaterWithUndo(BuildContext context, DateTime date, int ml, String source) async {
  final repo = WaterRepo(context.db);
  final id = await repo.add(date, ml, source);
  if (context.mounted) showUndo(context, 'Added ${fmtInt(ml)} ml', () => repo.remove(id));
}

/// Removes an entry with Undo.
Future<void> removeWaterWithUndo(BuildContext context, Map<String, Object?> r) async {
  final repo = WaterRepo(context.db);
  await repo.remove(r['id'] as String);
  if (context.mounted) showUndo(context, 'Removed ${fmtInt(r['ml'] as num)} ml', () => repo.restore(r));
}

/// Edit amount and time of an entry. Includes a Delete action.
Future<void> editWaterEntry(BuildContext context, Map<String, Object?> r) async {
  final repo = WaterRepo(context.db);
  final result = await showDialog<_EditResult>(
    context: context,
    builder: (_) => _EditWaterDialog(row: r),
  );
  if (result == null || !context.mounted) return;
  if (result.delete) {
    await removeWaterWithUndo(context, r);
  } else {
    await repo.update(r, ml: result.ml, at: result.at);
    if (context.mounted) showUndo(context, 'Updated to ${fmtInt(result.ml)} ml', () => repo.restore(r));
  }
}

class _EditResult {
  _EditResult({this.ml = 0, DateTime? at, this.delete = false}) : at = at ?? DateTime.now();
  final int ml;
  final DateTime at;
  final bool delete;
}

class _EditWaterDialog extends StatefulWidget {
  const _EditWaterDialog({required this.row});
  final Map<String, Object?> row;

  @override
  State<_EditWaterDialog> createState() => _EditWaterDialogState();
}

class _EditWaterDialogState extends State<_EditWaterDialog> {
  late final _ml = TextEditingController(text: '${(widget.row['ml'] as num).toInt()}');
  late DateTime _time = _at(widget.row);

  int? get _value {
    final v = int.tryParse(_ml.text.trim());
    return v != null && v > 0 && v <= 5000 ? v : null;
  }

  void _save() {
    final v = _value;
    if (v != null) Navigator.pop(context, _EditResult(ml: v, at: _time));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit water'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ml,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: 'ml',
                errorText: _ml.text.isNotEmpty && _value == null ? 'Enter 1–5,000 ml' : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final v in const [150, 250, 500, 750])
                  ChoiceChip(
                    label: Text('$v ml'),
                    selected: _value == v,
                    onSelected: (_) => setState(() => _ml.text = '$v'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text('${DateFormat('EEE d MMM').format(_time)} · ${DateFormat.Hm().format(_time)}'),
              subtitle: Text('Added ${waterSourceLabels[widget.row['source']] ?? ''}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time));
                if (t != null) {
                  setState(() => _time = DateTime(_time.year, _time.month, _time.day, t.hour, t.minute));
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: context.cs.error),
          onPressed: () => Navigator.pop(context, _EditResult(delete: true)),
          child: const Text('Delete'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _value == null ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

/// One entry: water icon · "250 ml" over "19:29 · from Overview" · ✕.
/// Tap the row to edit amount/time.
class WaterEntryTile extends StatelessWidget {
  const WaterEntryTile({super.key, required this.row, this.divider = true});
  final Map<String, Object?> row;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final sem = context.sem;
    final ml = fmtInt(row['ml'] as num);
    final time = DateFormat.Hm().format(_at(row));
    final source = row['source'] as String?;
    return Semantics(
      button: true,
      label: 'Edit $ml ml at $time',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => editWaterEntry(context, row),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: divider
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: context.cs.outlineVariant)),
                )
              : null,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: sem.waterContainer,
                foregroundColor: sem.water,
                child: Icon(_sourceIcons[source] ?? Icons.water_drop_outlined, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$ml ml', style: context.tt.titleSmall),
                    Text([time, ?waterSourceLabels[source]].join(' · '), style: context.tt.bodySmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove $ml ml at $time',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => removeWaterWithUndo(context, row),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with a day's entries (opened from the Today water card).
Future<void> showWaterEntriesSheet(BuildContext context, DateTime date) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => _WaterSheet(date: date),
);

class _WaterSheet extends ConsumerWidget {
  const _WaterSheet({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: AsyncBody(
          value: ref.watch(waterEntriesProvider(dayKey(date))),
          builder: (context, rows) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Water · ${relativeDay(date)}', style: context.tt.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Tap an entry to change it.', style: context.tt.bodySmall),
              ),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('No water logged yet', style: context.tt.bodySmall),
                ),
              for (final (i, r) in rows.indexed) WaterEntryTile(row: r, divider: i < rows.length - 1),
            ],
          ),
        ),
      ),
    );
  }
}
