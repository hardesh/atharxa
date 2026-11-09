import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_info.dart';
import '../../../state/ai_controller.dart';
import '../../../state/reminders_controller.dart';
import '../../../state/settings_providers.dart';
import '../../../state/strava_controller.dart';
import '../../../state/sync_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import 'about_page.dart';
import 'ai_models_page.dart';
import 'appearance_page.dart';
import 'connected_services_page.dart';
import 'body_stats_page.dart';
import 'data_backup_page.dart';
import 'device_sync_page.dart';
import 'goals_page.dart';
import 'reminders_page.dart';

/// A section of You: hub row + its page.
class YouSection {
  const YouSection(this.id, this.title, this.icon, this.page);
  final String id, title;
  final IconData icon;

  /// null → not built yet ("coming soon").
  final WidgetBuilder? page;
}

final youSections = <YouSection>[
  YouSection('goals', 'Goals', Icons.flag_outlined, (_) => const GoalsPage()),
  YouSection('appearance', 'Appearance', Icons.palette_outlined, (_) => const AppearancePage()),
  YouSection('reminders', 'Reminders', Icons.notifications_none, (_) => const RemindersPage()),
  YouSection('sync', 'Device sync', Icons.sync, (_) => const DeviceSyncPage()),
  YouSection('services', 'Connected services', Icons.link, (_) => const ConnectedServicesPage()),
  YouSection('ai', 'AI models', Icons.auto_awesome_outlined, (_) => const AiModelsPage()),
  YouSection('body', 'Body stats', Icons.monitor_weight_outlined, (_) => const BodyStatsPage()),
  YouSection('data', 'Data and backup', Icons.backup_outlined, (_) => const DataBackupPage()),
  YouSection('about', 'About', Icons.info_outline, (_) => const AboutPage()),
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
      final (enabled, last) = ref.watch(syncControllerProvider.select((s) => (s.enabled, s.lastSync)));
      if (!enabled) return 'Off';
      return last == null ? 'On · not paired yet' : 'On · synced ${fmtWhen(last)}';
    case 'reminders':
      final r = ref.watch(remindersProvider);
      final on = [if (r.mealsOn.values.any((v) => v)) 'Meals', if (r.waterOn) 'Water', if (r.checkinOn) 'Check-ins'];
      return on.isEmpty ? 'Off' : on.join(' · ');
    case 'body':
      final b = ref.watch(syncedSettingsProvider.select((s) => s.body));
      if (b.heightCm == null && b.weightKg == null) return 'Height, weight, activity';
      return [
        if (b.heightCm != null) '${fmtInt(b.heightCm!)} cm',
        if (b.weightKg != null) '${fmtGrams(b.weightKg!)} kg',
        b.activity.label,
      ].join(' · ');
    case 'data':
      final last = ref.watch(deviceSettingsProvider.select((s) => s.lastBackupAt));
      return last == null ? 'Export or restore everything' : 'Last backup ${fmtWhen(last)}';
    case 'services':
      final strava = ref.watch(stravaProvider);
      return strava.connected ? 'Strava · ${strava.account!.athlete ?? 'connected'}' : 'Strava, workout tips';
    case 'ai':
      final m = ref.watch(aiProvider.select((s) => s.active));
      return m == null ? 'Download a model for the assistant' : m.name;
    case 'about':
      return '${AppInfo.name} ${AppInfo.version}';
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

/// Two panes need room for a 344 px section list plus a usable page.
const _twoPaneMinWidth = 900.0;

class _YouScreenState extends ConsumerState<YouScreen> {
  bool get _twoPane => MediaQuery.sizeOf(context).width >= _twoPaneMinWidth;

  String _selected = 'sync';

  void _open(YouSection s) {
    if (_twoPane) {
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
      padding: EdgeInsets.fromLTRB(_twoPane ? 16 : context.screenPad, 4, _twoPane ? 16 : context.screenPad, 24),
      children: [
        const _ProfileCard(),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final (i, s) in youSections.indexed) ...[
                if (i > 0) const Divider(indent: 56),
                ListTile(
                  selected: _twoPane && s.id == _selected,
                  selectedTileColor: context.cs.secondaryContainer,
                  leading: Icon(s.icon),
                  title: Text(s.title),
                  subtitle: Text(_summary(s.id, ref) ?? ''),
                  trailing: _twoPane ? null : const Icon(Icons.chevron_right),
                  onTap: () => _open(s),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    if (!_twoPane) return hub;

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
          final name = await askText(
            context,
            title: 'Your name',
            label: 'Name',
            initial: s.profileName,
            capitalization: TextCapitalization.words,
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
