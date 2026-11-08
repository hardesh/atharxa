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
import '../../widgets/tag.dart';

/// "482913" → "482 913".
String formatCode(String c) => c.length == 6 ? '${c.substring(0, 3)} ${c.substring(3)}' : c;

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
    // A code mismatch opens a dialog with the fix.
    ref.listenManual(syncControllerProvider.select((s) => s.failure), (prev, next) {
      final e = next?.error;
      if (e != null && e.kind == SyncErrorKind.codeMismatch && !identical(prev, next) && mounted) {
        _showMismatch(e.peer ?? 'The other device');
      }
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
    if (again == true) {
      await _ctl.syncNow();
    } else if (again == false && mounted) {
      _codeFocus.requestFocus();
    }
  }

  Future<void> _addByIp() async {
    final address = await askText(
      context,
      title: 'Add device by IP',
      label: 'IP address',
      hint: '192.168.1.42',
      message: 'On the other device, open You › Device sync. Its address is shown under "Sync with my devices".',
      confirmLabel: 'Connect',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (address != null && address.isNotEmpty) await _ctl.addByAddress(address);
  }

  @override
  Widget build(BuildContext context) {
    // Only what this page shows; progress ticks rebuild just _StatusCard.
    final (:enabled, :listening, :address, :paired, :discovered, :busy, :autoSync, :intervalMin) = ref.watch(
      syncControllerProvider.select(
        (s) => (
          enabled: s.enabled,
          listening: s.listening,
          address: s.address,
          paired: s.paired,
          discovered: s.discovered,
          busy: s.busy,
          autoSync: s.autoSync,
          intervalMin: s.intervalMin,
        ),
      ),
    );
    if (!enabled) return _OffState(onTurnOn: () => _ctl.setEnabled(true));

    final newDevices = discovered.values.where((d) => !paired.any((p) => p.id == d.id)).toList();
    final addr = address == null ? 'not connected to Wi-Fi' : '$address : $syncPort';
    return PageBody(
      children: [
        Card(
          child: SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            title: Text('Sync with my devices', style: context.tt.titleMedium),
            subtitle: Text(listening ? 'On · $addr' : 'Starting…'),
            value: true,
            onChanged: (_) => _ctl.setEnabled(false),
          ),
        ),
        const _StatusCard(),
        if (paired.isNotEmpty)
          _Section(
            title: 'Paired devices',
            child: Column(
              children: [
                for (final (i, p) in paired.indexed) ...[
                  if (i > 0) const Divider(),
                  _PairedTile(peer: p, online: discovered.containsKey(p.id), busy: busy),
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
              if (newDevices.isEmpty)
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
              for (final d in newDevices) _DiscoveredTile(peer: d, busy: busy, onPair: () => _ctl.pair(d)),
              TextButton(onPressed: busy ? null : _addByIp, child: const Text('Not listed? Add device by IP')),
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
                value: autoSync,
                onChanged: _ctl.setAutoSync,
              ),
              if (autoSync) ...[
                const SizedBox(height: 4),
                Text('Also every', style: context.tt.bodySmall),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1 min')),
                    ButtonSegment(value: 5, label: Text('5 min')),
                    ButtonSegment(value: 15, label: Text('15 min')),
                  ],
                  selected: {intervalMin},
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

/// Last sync / progress / Sync now, plus the latest failure.
class _StatusCard extends ConsumerWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final last = s.lastSync;
    final p = s.progress;
    final failure = s.failure;
    final title = s.busy ? 'Syncing…' : (last == null ? 'Not synced yet' : 'Last sync ${fmtWhen(last)}');
    final detail = p != null && p.total > 0
        ? 'received ${fmtInt(p.received)} of ${fmtInt(p.total)}'
        : (s.busy ? null : s.lastResult);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.tt.titleSmall),
                    if (detail != null) Text(detail, style: context.tt.bodySmall),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: !s.busy && s.paired.isNotEmpty ? ref.read(syncControllerProvider.notifier).syncNow : null,
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Sync now'),
              ),
            ],
          ),
          if (s.busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: p != null && p.total > 0 ? (p.received / p.total).clamp(0.0, 1.0) : null,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (failure != null && !s.busy) ...[
            const SizedBox(height: 12),
            failure.manual || failure.error.kind == SyncErrorKind.codeMismatch
                ? _ErrorBanner(error: failure.error)
                : Text('Last automatic attempt: ${_describe(failure.error)}', style: context.tt.bodySmall),
          ],
        ],
      ),
    );
  }
}

String _describe(SyncException e) => e.kind == SyncErrorKind.unreachable
    ? '${e.message}. Check it is on the same Wi-Fi with sync turned on.'
    : e.message;

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final SyncException error;

  @override
  Widget build(BuildContext context) => Container(
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
          child: Text(_describe(error), style: context.tt.bodyMedium?.copyWith(color: context.cs.onErrorContainer)),
        ),
      ],
    ),
  );
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
        'Sent ${peer.lastSent}, received ${peer.lastReceived} · ${fmtWhen(peer.lastSyncAt!)}',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.devices_outlined, size: 20)),
      title: Row(
        children: [
          Flexible(child: Text(peer.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          online ? Tag('Online', fg: sem.success, bg: sem.successContainer) : const Tag('Offline'),
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

/// Titled card section (primary-coloured heading).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.tt.titleSmall?.copyWith(color: context.cs.primary)),
        const SizedBox(height: 4),
        child,
      ],
    ),
  );
}
