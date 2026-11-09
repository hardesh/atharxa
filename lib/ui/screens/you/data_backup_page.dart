import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backup.dart';
import '../../../services/file_saver.dart';
import '../../../state/core_providers.dart';
import '../../../state/data_providers.dart';
import '../../../state/desktop_controller.dart';
import '../../../state/reminders_controller.dart';
import '../../../state/settings_providers.dart';
import '../../../state/sync_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../../app_clock.dart';

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
final _tables = _labels.keys.join(',');

/// You › Data and backup: export everything to one file; restore (merge) from
/// a backup with a preview first.
class DataBackupPage extends ConsumerWidget {
  const DataBackupPage({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final bytes = await Backup.create(
      ref.read(dbProvider),
      ref.read(prefsProvider),
      deviceName: ref.read(syncControllerProvider).deviceName,
    );
    final where = await saveExportedFile(Backup.fileName(AppClock.now()), bytes);
    if (where == null) return;
    await ref.read(deviceSettingsProvider.notifier).setBackedUp(AppClock.now());
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
        if (contents.counts[e.key] case final n? when n > 0) '${e.value}: ${fmtInt(n)}',
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
    final prefs = ref.read(prefsProvider);
    final applied = await Backup.restore(ref.read(dbProvider), prefs, contents);
    // Device settings were rewritten underneath their owners: reload them.
    ref
      ..invalidate(deviceSettingsProvider)
      ..invalidate(remindersProvider);
    if (ref.read(desktopControllerProvider).supported) {
      await ref.read(desktopControllerProvider.notifier).setMenuBar(prefs.getBool(DeviceKeys.menuBar) ?? true);
    }
    if (context.mounted) showMessage(context, 'Restored $applied ${applied == 1 ? 'entry' : 'entries'}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(dataCountsProvider(_tables)).value ?? const {};
    final last = ref.watch(deviceSettingsProvider.select((s) => s.lastBackupAt));
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
