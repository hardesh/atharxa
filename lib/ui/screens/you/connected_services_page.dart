import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/activity_import_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/layout.dart';

/// You › Connected services: workouts from Health Connect (Strava, Pixel
/// Watch, Fitbit) and where workout tips come from.
class ConnectedServicesPage extends ConsumerStatefulWidget {
  const ConnectedServicesPage({super.key});

  /// Pushed from Workout's "Runs and rides" card.
  static Future<void> open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Connected services')),
        body: const ConnectedServicesPage(),
      ),
    ),
  );

  @override
  ConsumerState<ConnectedServicesPage> createState() => _ConnectedServicesPageState();
}

class _ConnectedServicesPageState extends ConsumerState<ConnectedServicesPage> {
  @override
  void initState() {
    super.initState();
    ref.read(activityImportProvider.notifier).check();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(activityImportProvider);
    final ctl = ref.read(activityImportProvider.notifier);
    return PageBody(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_run, color: context.cs.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Runs, rides and other workouts', style: context.tt.titleMedium)),
                  if (s.granted) Text('Connected', style: context.tt.labelLarge?.copyWith(color: context.sem.success)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Read from Health Connect on your phone: activities from Strava, Pixel Watch, Fitbit and other '
                'apps that share with it. They appear in Workout and sync to your other devices.',
                style: context.tt.bodySmall,
              ),
              if (s.busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(s.error!, style: context.tt.bodyMedium?.copyWith(color: context.cs.error)),
                ),
              const SizedBox(height: 8),
              if (!s.supported)
                Text(
                  'Health Connect is on Android: turn it on in the app on your phone, and activities arrive here '
                  'with Wi-Fi sync.',
                  style: context.tt.bodyMedium,
                )
              else if (s.available == false)
                Text('Health Connect isn’t available on this phone.', style: context.tt.bodyMedium)
              else if (!s.granted)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: s.available == null ? null : ctl.connect,
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('Allow access to workouts'),
                  ),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.lastImport == null ? 'Not imported yet' : 'Last import ${fmtWhen(s.lastImport!)}'),
                  subtitle: s.message == null ? null : Text(s.message!),
                  trailing: TextButton(onPressed: s.busy ? null : ctl.importNow, child: const Text('Import now')),
                ),
              if (s.supported) ...[
                const Divider(height: 24),
                Text('Strava', style: context.tt.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'In the Strava app: You › ⚙ › Manage Apps and Devices › Health Connect, then allow everything. '
                  'Strava shares GPS activities (runs, rides, walks) with their time, distance and calories.',
                  style: context.tt.bodySmall,
                ),
              ],
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined, color: context.cs.primary),
                  const SizedBox(width: 12),
                  Text('Workout tips', style: context.tt.titleMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Form tips come from a built-in exercise library and work offline. Videos are the YouTube links '
                'you add to an exercise; they play in the app when you’re online.',
                style: context.tt.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
