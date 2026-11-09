import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_info.dart';
import '../../../state/strava_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import 'strava_sign_in.dart';

/// You › Connected services (DESIGN.md §5, §7.5): Strava (import runs and
/// rides, upload workouts) and where workout tips come from.
class ConnectedServicesPage extends ConsumerWidget {
  const ConnectedServicesPage({super.key});

  /// Pushed from Workout's "Connect Strava".
  static Future<void> open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Connected services')),
        body: const ConnectedServicesPage(),
      ),
    ),
  );

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final account = ref.read(stravaProvider).account!;
    final code = await StravaSignInPage.open(context, account.clientId);
    if (code == null) return;
    await ref.read(stravaProvider.notifier).connect(code);
    final s = ref.read(stravaProvider);
    if (context.mounted && s.connected) showMessage(context, 'Connected to Strava');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stravaProvider);
    final ctl = ref.read(stravaProvider.notifier);
    final a = s.account;
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
                  Expanded(child: Text('Strava', style: context.tt.titleMedium)),
                  if (s.connected)
                    Text('Connected', style: context.tt.labelLarge?.copyWith(color: context.sem.success)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Import runs and rides into Workout, and upload gym sessions. Imported activities sync to your '
                'other devices; the Strava sign-in stays on this one.',
                style: context.tt.bodySmall,
              ),
              if (s.busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(s.error!, style: context.tt.bodyMedium?.copyWith(color: context.cs.error)),
                ),
              const SizedBox(height: 8),
              if (a == null)
                _Credentials(onSave: ctl.setCredentials)
              else if (!a.connected) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Strava API app'),
                  subtitle: Text('Client ID ${a.clientId}'),
                  trailing: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Strava API app'),
                        content: _Credentials(
                          initialId: a.clientId,
                          onSave: (id, secret) async {
                            await ctl.setCredentials(id, secret);
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ),
                    ),
                    child: const Text('Change'),
                  ),
                ),
                Text(
                  '${AppInfo.name} will read your activities (including private ones) and upload workouts you choose.',
                  style: context.tt.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: s.busy ? null : () => _connect(context, ref),
                  icon: const Icon(Icons.link),
                  label: const Text('Connect with Strava'),
                ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.athlete ?? 'Your Strava account'),
                  subtitle: Text(
                    [
                      if (a.lastImportAt != null) 'Last import ${fmtWhen(a.lastImportAt!)}' else 'Not imported yet',
                      ?s.message,
                    ].join(' · '),
                  ),
                  trailing: TextButton(onPressed: s.busy ? null : ctl.importNow, child: const Text('Import now')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Upload workouts to Strava'),
                  subtitle: const Text('Default for the switch on Workout complete'),
                  value: a.uploadByDefault,
                  onChanged: ctl.setUploadByDefault,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: s.busy
                        ? null
                        : () async {
                            final ok = await confirm(
                              context,
                              title: 'Disconnect Strava?',
                              message: 'Imported activities stay. New ones stop arriving until you connect again.',
                              confirmLabel: 'Disconnect',
                            );
                            if (ok) await ctl.disconnect();
                          },
                    child: const Text('Disconnect'),
                  ),
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

/// Client ID + Secret of the user's own Strava API app, with how to make one.
class _Credentials extends StatefulWidget {
  const _Credentials({required this.onSave, this.initialId});
  final Future<void> Function(String id, String secret) onSave;
  final String? initialId;

  @override
  State<_Credentials> createState() => _CredentialsState();
}

class _CredentialsState extends State<_Credentials> {
  late final _id = TextEditingController(text: widget.initialId);
  final _secret = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Strava needs an API app of your own (free, about two minutes): at strava.com/settings/api create an '
        'app with Authorization Callback Domain “localhost”, then copy its Client ID and Client Secret here.',
        style: context.tt.bodySmall,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: 'https://www.strava.com/settings/api'));
            if (context.mounted) showMessage(context, 'Link copied');
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy the link'),
        ),
      ),
      TextField(
        controller: _id,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Client ID'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _secret,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Client Secret'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _id.text.trim().isEmpty || _secret.text.trim().isEmpty
            ? null
            : () => widget.onSave(_id.text.trim(), _secret.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
