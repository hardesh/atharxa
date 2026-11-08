import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/semantic.dart';
import 'layout.dart';

/// Shared top bar (DESIGN.md §4).
/// Phone: title · round AI button · avatar (opens You).
/// Mac/wide: headline title · "Ask Atharxa ⌘K" pill · avatar with sync dot.
class AtharxaTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AtharxaTopBar({super.key, required this.title, this.onOpenYou, this.actions = const []});

  final String title;
  final VoidCallback? onOpenYou;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final wide = context.isWide;
    final settings = context.settings;
    final sync = AppScope.of(context).sync;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? contentMaxWidth + 64 : double.infinity),
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
                      label: const Text('Ask Atharxa  ⌘K'),
                    )
                  else
                    Semantics(
                      label: 'Ask Atharxa',
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
                  ListenableBuilder(
                    listenable: Listenable.merge([settings, sync]),
                    builder: (context, _) => Semantics(
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
                              child: Text(
                                settings.initial,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (wide && sync.running)
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
              Text('Atharxa assistant', style: ctx.tt.titleLarge),
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
