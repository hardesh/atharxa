import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/water_repo.dart';
import '../../state/core_providers.dart';
import '../../state/data_providers.dart';
import '../format.dart';
import '../theme/semantic.dart';
import 'feedback.dart';
import '../../app_clock.dart';

/// Where an entry was added: label + icon. Stored keys stay stable ('today' = the Overview card).
const _sources = {
  'today': (label: 'from Overview', icon: Icons.dashboard_outlined),
  'water': (label: 'from Water', icon: Icons.water_drop_outlined),
  'notification': (label: 'from a reminder', icon: Icons.notifications_none),
  'mac': (label: 'on Mac', icon: Icons.laptop_mac),
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
  _EditResult({this.ml = 0, DateTime? at, this.delete = false}) : at = at ?? AppClock.now();
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
              title: Text('${fmtDayShort(_time)} · ${fmtTime(_time)}'),
              subtitle: Text('Added ${_sources[widget.row['source']]?.label ?? ''}'),
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

/// A day's entries with dividers between rows, or an empty message.
class WaterEntryList extends StatelessWidget {
  const WaterEntryList({super.key, required this.rows});
  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No water logged yet', style: context.tt.bodySmall),
      );
    }
    return Column(
      children: [
        for (final (i, r) in rows.indexed) ...[if (i > 0) const Divider(), WaterEntryTile(row: r)],
      ],
    );
  }
}

/// Water-tinted circular badge (Overview water card, entry rows).
class WaterBadge extends StatelessWidget {
  const WaterBadge({super.key, this.icon = Icons.water_drop_outlined, this.radius = 20, this.iconSize = 24});
  final IconData icon;
  final double radius, iconSize;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: context.sem.waterContainer,
    foregroundColor: context.sem.water,
    child: Icon(icon, size: iconSize),
  );
}

/// One entry: water badge · "250 ml" over "19:29 · from Overview" · ✕.
/// Tap the row to edit amount/time.
class WaterEntryTile extends StatelessWidget {
  const WaterEntryTile({super.key, required this.row});
  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final ml = fmtInt(row['ml'] as num);
    final time = fmtTime(_at(row));
    final source = _sources[row['source']];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: WaterBadge(icon: source?.icon ?? Icons.water_drop_outlined, radius: 18, iconSize: 18),
      title: Text('$ml ml', style: context.tt.titleSmall),
      subtitle: Text([time, ?source?.label].join(' · ')),
      trailing: IconButton(
        tooltip: 'Remove $ml ml at $time',
        icon: const Icon(Icons.close, size: 20),
        onPressed: () => removeWaterWithUndo(context, row),
      ),
      onTap: () => editWaterEntry(context, row),
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
              WaterEntryList(rows: rows),
            ],
          ),
        ),
      ),
    );
  }
}
