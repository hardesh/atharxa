import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_info.dart';
import '../../../state/settings_providers.dart';
import '../../../state/sync_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import 'device_sync_page.dart';

/// A section of You: hub row + its page.
class YouSection {
  const YouSection(this.id, this.title, this.icon, this.page);
  final String id, title;
  final IconData icon;

  /// null → not built yet ("coming soon").
  final WidgetBuilder? page;
}

final youSections = <YouSection>[
  const YouSection('goals', 'Goals', Icons.flag_outlined, null),
  const YouSection('appearance', 'Appearance', Icons.palette_outlined, null),
  const YouSection('reminders', 'Reminders', Icons.notifications_none, null),
  YouSection('sync', 'Device sync', Icons.sync, (_) => const DeviceSyncPage()),
  const YouSection('services', 'Connected services', Icons.link, null),
  const YouSection('ai', 'AI models', Icons.auto_awesome_outlined, null),
  const YouSection('body', 'Body stats', Icons.monitor_weight_outlined, null),
  const YouSection('data', 'Data and backup', Icons.backup_outlined, null),
  const YouSection('about', 'About', Icons.info_outline, null),
];

/// One-line summaries under each hub row.
String? _summary(String id, WidgetRef ref) {
  switch (id) {
    case 'goals':
      final g = ref.watch(goalsProvider);
      return '${fmtInt(g.kcal)} kcal · ${fmtInt(g.waterMl)} ml water';
    case 'appearance':
      final p = ref.watch(syncedSettingsProvider.select((s) => s.palette));
      final d = ref.watch(deviceSettingsProvider);
      return '${p.label} · ${d.themeMode.name[0].toUpperCase()}${d.themeMode.name.substring(1)} · ${(d.textScale * 100).round()}%';
    case 'sync':
      final s = ref.watch(syncControllerProvider);
      if (!s.enabled) return 'Off';
      final last = s.paired
          .map((p) => p.lastSyncAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      return last == null ? 'On · not paired yet' : 'On · synced ${whenText(last)}';
    case 'about':
      return AppInfo.name;
    default:
      return 'Coming soon';
  }
}

/// You (DESIGN.md §5, You.dc.html): profile card + sections.
/// Phone: hub list; each row pushes its page. Wide/Mac: two panes.
class YouScreen extends ConsumerStatefulWidget {
  const YouScreen({super.key});

  @override
  ConsumerState<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends ConsumerState<YouScreen> {
  String _selected = 'sync';

  void _open(YouSection s) {
    if (context.isWide) {
      setState(() => _selected = s.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(s.title)),
          body: s.page?.call(context) ?? _ComingSoon(section: s),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = ListView(
      padding: EdgeInsets.fromLTRB(
        context.isWide ? 16 : context.screenPad,
        4,
        context.isWide ? 16 : context.screenPad,
        24,
      ),
      children: [
        const _ProfileCard(),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final (i, s) in youSections.indexed) ...[
                if (i > 0) const Divider(indent: 56),
                ListTile(
                  selected: context.isWide && s.id == _selected,
                  selectedTileColor: context.cs.secondaryContainer,
                  leading: Icon(s.icon),
                  title: Text(s.title),
                  subtitle: Text(_summary(s.id, ref) ?? ''),
                  trailing: context.isWide ? null : const Icon(Icons.chevron_right),
                  onTap: () => _open(s),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    if (!context.isWide) return hub;

    final section = youSections.firstWhere((s) => s.id == _selected);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 344, child: hub),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(section.title, style: context.tt.titleLarge),
              ),
              Expanded(child: section.page?.call(context) ?? _ComingSoon(section: section)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncedSettingsProvider);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: context.cs.secondaryContainer,
          foregroundColor: context.cs.onSecondaryContainer,
          child: Text(s.initial, style: context.tt.titleLarge?.copyWith(color: context.cs.onSecondaryContainer)),
        ),
        title: Text(s.profileName.isEmpty ? 'Add your name' : s.profileName, style: context.tt.titleMedium),
        subtitle: const Text('Profile and body stats'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () async {
          final c = TextEditingController(text: s.profileName);
          final name = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Your name'),
              content: TextField(
                controller: c,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
              ],
            ),
          );
          if (name != null) await ref.read(syncedSettingsProvider.notifier).setProfileName(name);
        },
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.section});
  final YouSection section;

  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(icon: section.icon, title: section.title, message: 'This section arrives in an upcoming update.'),
  );
}
