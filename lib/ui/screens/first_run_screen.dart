import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../data/currency.dart';
import '../../state/settings_providers.dart';
import '../theme/semantic.dart';
import 'finance/currency_picker.dart';
import 'you/goals_page.dart';

/// First run (DESIGN.md §5): welcome, daily goals (incl. fat), currency,
/// Start / Skip. Reuses the Goals form.
class FirstRunScreen extends ConsumerWidget {
  const FirstRunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(syncedSettingsProvider.select((s) => s.currency));
    final done = ref.read(deviceSettingsProvider.notifier).setFirstRunDone;
    return Scaffold(
      body: SafeArea(
        child: GoalsPage(
          saveLabel: 'Start',
          onSaved: done,
          onSkip: done,
          header: [
            const SizedBox(height: 16),
            Text('Welcome to ${AppInfo.name}', style: context.tt.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Track food, water, workouts and money — everything stays on your devices. '
              'Set your daily goals to start; you can change them any time in You › Goals.',
              style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Currency'),
              subtitle: Text('${Currency.of(currency).name} (${Currency.of(currency).symbol})'),
              trailing: const Icon(Icons.expand_more),
              onTap: () async {
                final c = await pickCurrency(context, selected: currency);
                if (c != null) await ref.read(syncedSettingsProvider.notifier).setCurrency(c);
              },
            ),
            Text('Daily goals', style: context.tt.titleMedium),
          ],
        ),
      ),
    );
  }
}
