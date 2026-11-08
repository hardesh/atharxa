import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/settings_providers.dart';
import '../../theme/palettes.dart';
import '../../theme/semantic.dart';
import '../../widgets/layout.dart';

/// You › Appearance (DESIGN.md §5): theme (synced), mode and text size
/// (this device only).
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(syncedSettingsProvider.select((s) => s.palette));
    final device = ref.watch(deviceSettingsProvider);
    final deviceCtl = ref.read(deviceSettingsProvider.notifier);
    final platformDefault = Platform.isAndroid ? 1.3 : 1.0;
    return PageBody(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme', style: context.tt.titleMedium),
              Text('Synced between devices', style: context.tt.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final p in AppPalette.values)
                    _ThemeSwatch(
                      palette: p,
                      selected: p == palette,
                      onTap: () => ref.read(syncedSettingsProvider.notifier).setPalette(p),
                    ),
                ],
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Mode', style: context.tt.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {device.themeMode},
                onSelectionChanged: (v) => deviceCtl.setThemeMode(v.first),
              ),
              const SizedBox(height: 20),
              Text('Text size', style: context.tt.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final size in DeviceSettings.textSizes)
                    ChoiceChip(
                      label: Text('${(size * 100).round()}%${size == platformDefault ? ' · default' : ''}'),
                      selected: device.textScale == size,
                      onSelected: (_) => deviceCtl.setTextScale(size),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Aa — The quick brown fox jumps over the lazy dog.', style: context.tt.bodyMedium),
            ],
          ),
        ),
        Text('Mode and text size apply to this device only.', style: context.tt.bodySmall),
      ],
    );
  }
}

/// Diagonal two-tone swatch (primary / primary container) with the name.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.palette, required this.selected, required this.onTap});

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = schemeFor(palette, Theme.of(context).brightness);
    return Semantics(
      selected: selected,
      button: true,
      label: '${palette.label} theme',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 104,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? context.cs.primary : context.cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [.5, .5],
                    colors: [scheme.primary, scheme.primaryContainer],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(palette.label, style: context.tt.titleSmall),
              Text(palette == AppPalette.forest ? 'Default' : ' ', style: context.tt.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
