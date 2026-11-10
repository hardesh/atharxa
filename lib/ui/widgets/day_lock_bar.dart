import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/settings_providers.dart';
import '../theme/semantic.dart';

/// Under the date switcher on Overview and Water when the selected day isn't
/// today: a past day is locked (Unlock to edit) or unlocked (Lock); a future
/// day can't be logged at all.
class DayLockBar extends ConsumerWidget {
  const DayLockBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(dayAccessProvider);
    final unlock = ref.read(unlockedDayProvider.notifier);
    final (icon, text, action) = switch (access) {
      DayAccess.today => (null, '', null),
      DayAccess.lockedPast => (
        Icons.lock_outline,
        'Past day · locked',
        TextButton(
          onPressed: () => unlock.unlock(dayKey(ref.read(selectedDayProvider))),
          child: const Text('Unlock to edit'),
        ),
      ),
      DayAccess.unlockedPast => (
        Icons.lock_open,
        'Editing a past day',
        TextButton(onPressed: unlock.lock, child: const Text('Lock')),
      ),
      DayAccess.future => (Icons.event_outlined, 'Future day · log it on the day, or plan it in Meal plan', null),
    };
    if (icon == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      decoration: BoxDecoration(color: context.cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(text, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
