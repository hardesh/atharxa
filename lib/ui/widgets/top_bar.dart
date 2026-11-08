import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../state/sync_controller.dart';
import '../../state/settings_providers.dart';
import '../theme/semantic.dart';
import 'layout.dart';

/// Shared top bar (DESIGN.md §4).
/// Phone: title · round AI button · avatar (opens You).
/// Mac/wide: headline title · "Ask `assistant` ⌘K" pill · avatar with sync dot.
class AppTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, required this.title, this.onOpenYou, this.actions = const [], this.fullWidth = false});

  final String title;
  final VoidCallback? onOpenYou;
  final List<Widget> actions;

  /// Wide layouts normally centre the header on the content column; pages with
  /// their own multi-pane layout (You) span the full width instead.
  final bool fullWidth;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.cs;
    final wide = context.isWide;
    final initial = ref.watch(syncedSettingsProvider.select((s) => s.initial));
    final syncing = ref.watch(syncControllerProvider.select((s) => s.listening));
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide && !fullWidth ? contentMaxWidth + 64 : double.infinity),
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: EdgeInsets.only(left: wide ? 32 : 16, right: wide ? 32 : 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (wide ? context.tt.headlineMedium : context.tt.titleLarge)?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ...actions,
                  const SizedBox(width: 6),
                  if (wide)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
                      ),
                      onPressed: () => showAssistantComingSoon(context),
                      icon: const Icon(Icons.auto_awesome, size: 20),
                      label: const Text('Ask ${AppInfo.assistantName}  ⌘K'),
                    )
                  else
                    Semantics(
                      label: 'Ask ${AppInfo.assistantName}',
                      button: true,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          fixedSize: const Size(44, 44),
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        onPressed: () => showAssistantComingSoon(context),
                        icon: const Icon(Icons.auto_awesome, size: 22),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Builder(
                    builder: (context) => Semantics(
                      label: 'You: profile and settings',
                      button: true,
                      child: InkResponse(
                        onTap: onOpenYou,
                        radius: 24,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: cs.secondaryContainer,
                              foregroundColor: cs.onSecondaryContainer,
                              child: Text(initial, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            ),
                            if (wide && syncing)
                              Positioned(
                                right: -1,
                                bottom: -1,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: context.sem.success,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cs.surface, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder until the on-device assistant ships (Milestone 6).
void showAssistantComingSoon(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: ctx.cs.primary),
              const SizedBox(width: 12),
              Text('${AppInfo.assistantName} assistant', style: ctx.tt.titleLarge),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'The on-device assistant (Gemma 4, with Qwen as an option) is coming in a later version. '
            'It will answer questions about your food, water, workouts and spending — entirely on this device.',
            style: ctx.tt.bodyMedium,
          ),
        ],
      ),
    ),
  );
}
