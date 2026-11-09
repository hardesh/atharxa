import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backup.dart';
import '../../../services/file_saver.dart';
import '../../../state/core_providers.dart';
import '../../../state/data_providers.dart';
import '../../../state/reminders_controller.dart';
import '../../../state/settings_providers.dart';
import '../../../state/sync_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';

/// What each synced table is called on this page.
const _labels = {
  'food_logs': 'Food entries',
  'foods': 'Foods',
  'meal_plans': 'Meal plan items',
  'water_logs': 'Water entries',
  'transactions': 'Transactions',
  'workout_plans': 'Workout plans',
  'sessions': 'Workouts',
};

/// You › Data and backup: export everything to one file; restore (merge) from
/// a backup with a preview first.
class DataBackupPage extends ConsumerWidget {
  const DataBackupPage({super.key});

  static const _lastKey = 'last_backup_at';

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final prefs = ref.read(prefsProvider);
    final bytes = await Backup.create(
      ref.read(dbProvider),
      prefs,
      deviceName: ref.read(syncControllerProvider).deviceName,
    );
    final where = await saveExportedFile(Backup.fileName(DateTime.now()), bytes);
    if (where == null) return;
    await prefs.setString(_lastKey, DateTime.now().toIso8601String());
    ref.invalidate(dataCountsProvider); // refresh "last backup" line
    if (context.mounted) showMessage(context, 'Backup saved to $where');
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final text = await openTextFile(extensions: const ['json']);
    if (text == null || !context.mounted) return;
    final BackupContents contents;
    try {
      contents = Backup.read(text);
    } on FormatException catch (e) {
      showMessage(context, e.message);
      return;
    }
    final summary = [
      for (final e in _labels.entries)
        if (contents.count(e.key) > 0) '${e.value}: ${fmtInt(contents.count(e.key))}',
    ].join('\n');
    final ok = await confirm(
      context,
      title: 'Restore this backup?',
      message:
          '${contents.createdAt == null ? 'Backup' : 'Made ${fmtWhen(contents.createdAt!)}'}'
          '${contents.device == null ? '' : ' on ${contents.device}'}.\n\n$summary\n\n'
          'Entries are merged: anything newer on this device is kept, nothing is duplicated, '
          'and restored entries sync to your other devices.',
      confirmLabel: 'Restore',
    );
    if (!ok || !context.mounted) return;
    final applied = await Backup.restore(ref.read(dbProvider), ref.read(prefsProvider), contents);
    // Device settings were rewritten underneath these providers.
    ref
      ..invalidate(deviceSettingsProvider)
      ..invalidate(remindersProvider);
    if (context.mounted) showMessage(context, 'Restored $applied ${applied == 1 ? 'entry' : 'entries'}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(dataCountsProvider).value ?? const {};
    final last = DateTime.tryParse(ref.read(prefsProvider).getString(_lastKey) ?? '');
    return PageBody(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('On this device', style: context.tt.titleMedium),
              const SizedBox(height: 8),
              for (final e in _labels.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.value, style: context.tt.bodyMedium)),
                      Text(fmtInt(counts[e.key] ?? 0), style: context.tt.bodyMedium),
                    ],
                  ),
                ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Back up', style: context.tt.titleMedium),
              const SizedBox(height: 4),
              Text(
                last == null ? 'No backup made on this device yet.' : 'Last backup ${fmtWhen(last)}.',
                style: context.tt.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _export(context, ref),
                icon: const Icon(Icons.save_alt),
                label: const Text('Export backup'),
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Restore', style: context.tt.titleMedium),
              const SizedBox(height: 4),
              Text('Pick a backup file. You’ll see what’s in it before anything changes.', style: context.tt.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _restore(context, ref),
                icon: const Icon(Icons.restore),
                label: const Text('Restore from backup…'),
              ),
            ],
          ),
        ),
        Text(
          'A backup contains everything that syncs plus this device’s reminders, mode and text size. '
          'Pairing codes and paired devices aren’t included. With Wi-Fi sync on, your other device is '
          'already a live copy — backups protect against losing both.',
          style: context.tt.bodySmall,
        ),
      ],
    );
  }
}
