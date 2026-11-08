import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/sync_controller.dart';
import '../../../sync/discovery.dart';
import '../../../sync/peers.dart';
import '../../../sync/sync_protocol.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';

/// "482913" → "482 913".
String formatCode(String c) => c.length == 6 ? '${c.substring(0, 3)} ${c.substring(3)}' : c;

/// "today, 13:12" / "yesterday, 08:05" / "Sun 8 Nov, 13:12".
String whenText(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  final day = switch (days) {
    0 => 'today',
    1 => 'yesterday',
    _ => fmtDayShort(t),
  };
  return '$day, ${fmtTime(t)}';
}

/// Device sync (DESIGN.md §5 You › Device sync, §7.2; Pairing.dc.html).
class DeviceSyncPage extends ConsumerStatefulWidget {
  const DeviceSyncPage({super.key});

  @override
  ConsumerState<DeviceSyncPage> createState() => _DeviceSyncPageState();
}

class _DeviceSyncPageState extends ConsumerState<DeviceSyncPage> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  SyncController get _ctl => ref.read(syncControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    final s = ref.read(syncControllerProvider);
    _name.text = s.deviceName;
    _code.text = s.code;
    // Show the mismatch dialog whenever a session fails on the code.
    ref.listenManual(syncControllerProvider.select((s) => s.mismatchPeer), (_, peer) {
      if (peer != null && mounted) _showMismatch(peer);
    });
    ref.listenManual(syncControllerProvider.select((s) => s.code), (_, code) {
      if (_code.text != code) _code.text = code;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _showMismatch(String peer) async {
    final code = ref.read(syncControllerProvider).code;
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.sync_problem, color: ctx.cs.error),
        title: const Text('Pairing code does not match'),
        content: Text(
          '$peer is using a different code. Open You › Device sync on $peer and enter '
          '${formatCode(code)}, then tap Try again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Change my code')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Try again')),
        ],
      ),
    );
    _ctl.dismissMismatch();
    if (again == true) {
      await _ctl.syncNow();
    } else if (again == false && mounted) {
      FocusScope.of(context).requestFocus(_codeFocus);
    }
  }

  Future<void> _addByIp() async {
    final c = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add device by IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'On the other device, open You › Device sync. Its address is shown under "Sync with my devices".',
              style: ctx.tt.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'IP address', hintText: '192.168.1.42'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Connect')),
        ],
      ),
    );
    if (address != null && address.isNotEmpty) await _ctl.addByAddress(address);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncControllerProvider);
    if (!s.enabled) return _OffState(onTurnOn: () => _ctl.setEnabled(true));

    final addr = s.addresses.isEmpty ? 'not connected to Wi-Fi' : '${s.addresses.first} : $syncPort';
    return PageBody(
      children: [
        Card(
          child: SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            title: Text('Sync with my devices', style: context.tt.titleMedium),
            subtitle: Text(s.listening ? 'On · $addr' : 'Starting…'),
            value: true,
            onChanged: (_) => _ctl.setEnabled(false),
          ),
        ),
        _StatusCard(state: s, onSyncNow: _ctl.syncNow),
        if (s.paired.isNotEmpty)
          _Section(
            title: 'Paired devices',
            child: Column(
              children: [
                for (final (i, p) in s.paired.indexed) ...[
                  if (i > 0) const Divider(),
                  _PairedTile(peer: p, online: s.isOnline(p.id), busy: s.busyPeer != null),
                ],
              ],
            ),
          ),
        _Section(
          title: 'This device',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'This device’s name'),
                textInputAction: TextInputAction.done,
                onSubmitted: _ctl.setDeviceName,
                onTapOutside: (_) => _ctl.setDeviceName(_name.text),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      focusNode: _codeFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      style: context.tt.titleMedium?.copyWith(letterSpacing: 4),
                      decoration: const InputDecoration(
                        labelText: 'Pairing code',
                        helperText: 'Enter this same code on your other device',
                        helperMaxLines: 2,
                      ),
                      onChanged: (v) {
                        if (v.length == 6) _ctl.setCode(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(onPressed: _ctl.generateCode, child: const Text('New code')),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Section(
          title: 'On this network',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.unpaired.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('Searching…', style: context.tt.bodyMedium),
                    ],
                  ),
                ),
              for (final d in s.unpaired)
                _DiscoveredTile(peer: d, busy: s.busyPeer != null, onPair: () => _ctl.pair(d)),
              TextButton(
                onPressed: s.busyPeer == null ? _addByIp : null,
                child: const Text('Not listed? Add device by IP'),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Automatic sync',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sync automatically'),
                subtitle: const Text('A few seconds after a change, when the app opens, and on a timer'),
                value: s.autoSync,
                onChanged: _ctl.setAutoSync,
              ),
              if (s.autoSync) ...[
                const SizedBox(height: 4),
                Text('Also every', style: context.tt.bodySmall),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 min')),
                    ButtonSegment(value: 5, label: Text('5 min')),
                    ButtonSegment(value: 15, label: Text('15 min')),
                  ],
                  selected: {s.intervalMin},
                  onSelectionChanged: (v) => _ctl.setIntervalMin(v.first),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Food log, foods, meal plans, water, transactions and goals sync over your local Wi-Fi only — '
            'nothing goes to the cloud. Newest edit wins when the same entry changed on both devices. '
            'Reminders, light/dark mode and text size stay per device.',
            style: context.tt.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _OffState extends StatelessWidget {
  const _OffState({required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          title: Text('Sync with my devices', style: context.tt.titleMedium),
          trailing: Text('Off', style: context.tt.bodyMedium),
        ),
      ),
      EmptyState(
        icon: Icons.devices_outlined,
        title: 'No paired devices',
        message:
            'Sync goals, food log, meal plans, foods and transactions with your other device over your '
            'home Wi-Fi. Nothing leaves your network.',
        action: FilledButton(onPressed: onTurnOn, child: const Text('Turn on sync')),
      ),
    ],
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.onSyncNow});
  final SyncState state;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final last = s.paired
        .map((p) => p.lastSyncAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final error = s.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.busyPeer != null
                            ? 'Syncing…'
                            : last == null
                            ? 'Not synced yet'
                            : 'Last sync ${whenText(last)}',
                        style: context.tt.titleSmall,
                      ),
                      if (s.progress case final p? when p.total > 0)
                        Text('received ${fmtInt(p.received)} of ${fmtInt(p.total)}', style: context.tt.bodySmall)
                      else if (s.busyPeer == null && s.lastResult != null)
                        Text(s.lastResult!, style: context.tt.bodySmall),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: s.busyPeer == null && s.paired.isNotEmpty ? onSyncNow : null,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync now'),
                ),
              ],
            ),
            if (s.busyPeer != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: switch (s.progress) {
                  final p? when p.total > 0 => (p.received / p.total).clamp(0.0, 1.0),
                  _ => null,
                },
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(
                      error.kind == SyncErrorKind.interrupted ? Icons.sync_problem : Icons.error_outline,
                      color: context.cs.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        error.kind == SyncErrorKind.unreachable
                            ? '${error.message}. Check it is on the same Wi-Fi with sync turned on.'
                            : error.message,
                        style: context.tt.bodyMedium?.copyWith(color: context.cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PairedTile extends ConsumerWidget {
  const _PairedTile({required this.peer, required this.online, required this.busy});
  final PairedPeer peer;
  final bool online, busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(syncControllerProvider.notifier);
    final sem = context.sem;
    final detail = [
      peer.host,
      if (peer.lastSyncAt != null)
        'Sent ${peer.lastSent}, received ${peer.lastReceived} · ${whenText(peer.lastSyncAt!)}',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.devices_outlined, size: 20)),
      title: Row(
        children: [
          Flexible(child: Text(peer.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          _Tag(
            label: online ? 'Online' : 'Offline',
            fg: online ? sem.success : context.cs.onSurfaceVariant,
            bg: online ? sem.successContainer : context.cs.surfaceContainerHigh,
          ),
        ],
      ),
      subtitle: Text(detail),
      trailing: PopupMenuButton<String>(
        tooltip: 'Options for ${peer.name}',
        enabled: !busy,
        onSelected: (v) async {
          if (v == 'full') {
            final ok = await confirm(
              context,
              title: 'Full resync with ${peer.name}?',
              message:
                  'Sends and receives every entry again. Use it if something looks out of sync. '
                  'Nothing is lost — the newest version of each entry is kept.',
              confirmLabel: 'Full resync',
            );
            if (ok) await ctl.fullResync(peer);
          } else {
            final ok = await confirm(
              context,
              title: 'Forget ${peer.name}?',
              message: 'Stops syncing with this device. Data already synced stays on both devices.',
              confirmLabel: 'Forget',
              destructive: true,
            );
            if (ok) await ctl.forget(peer);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'full', child: Text('Full resync')),
          PopupMenuItem(value: 'forget', child: Text('Forget device')),
        ],
      ),
    );
  }
}

class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.peer, required this.busy, required this.onPair});
  final DiscoveredPeer peer;
  final bool busy;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const CircleAvatar(child: Icon(Icons.devices_other_outlined, size: 20)),
    title: Text(peer.name),
    subtitle: Text('${peer.host} · ready to pair'),
    trailing: FilledButton(onPressed: busy ? null : onPair, child: const Text('Pair')),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.fg, required this.bg});
  final String label;
  final Color fg, bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: context.tt.labelMedium?.copyWith(color: fg)),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.tt.titleSmall?.copyWith(color: context.cs.primary)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    ),
  );
}
