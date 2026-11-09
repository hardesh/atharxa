import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_models.dart';
import '../../state/ai_controller.dart';
import '../format.dart';
import '../screens/assistant/assistant_screen.dart';
import '../screens/you/ai_models_page.dart';
import '../theme/semantic.dart';
import 'feedback.dart';
import 'layout.dart';

/// Model download status under the top bar on every main screen, so a
/// multi-gigabyte download never leaves the user guessing: progress (with
/// Cancel), "Checking the file…", "… is ready" (Open assistant), a failure
/// (Retry) or a download cut off by closing the app (Resume). Tapping it
/// opens AI models. Hidden when there is nothing to say.
class ModelDownloadBanner extends ConsumerWidget {
  const ModelDownloadBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aiProvider);
    final ai = ref.read(aiProvider.notifier);
    final cs = context.cs;

    Future<void> retry(AiModel m) async {
      final why = await ai.download(m);
      if (why != null && context.mounted) showMessage(context, why);
    }

    final downloading = s.downloads.entries.firstOrNull;
    final failed = s.errors.entries.firstOrNull;
    final (IconData icon, String title, String? detail, double? progress, List<Widget> actions)? content;
    if (downloading != null) {
      final m = s.model(downloading.key)!;
      final p = downloading.value;
      final checking = p >= 0.995;
      content = (
        Icons.downloading,
        checking ? 'Checking ${m.name}…' : 'Downloading ${m.name}',
        checking
            ? 'Making sure the file is complete'
            : '${(p * 100).floor()} % · ${fmtSize((m.sizeBytes * p).round())} of ${fmtSize(m.sizeBytes)} · keeps going in the background',
        p == 0 || checking ? null : p,
        [
          if (!checking)
            TextButton(
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Stop downloading ${m.name}?',
                  message: 'What has downloaded so far is discarded.',
                  confirmLabel: 'Stop download',
                );
                if (ok) ai.cancelDownload(m);
              },
              child: const Text('Cancel'),
            ),
        ],
      );
    } else if (s.model(s.readyId) case final m?) {
      content = (
        Icons.check_circle_outline,
        '${m.name} is ready',
        'The assistant now runs on ${deviceNoun(s.caps)}, offline',
        null,
        [
          TextButton(
            onPressed: () {
              ai.dismissNotices();
              openAssistant(context);
            },
            child: const Text('Open assistant'),
          ),
        ],
      );
    } else if (failed != null && s.model(failed.key) != null) {
      final m = s.model(failed.key)!;
      content = (
        Icons.error_outline,
        'Couldn’t download ${m.name}',
        failed.value,
        null,
        [TextButton(onPressed: () => retry(m), child: const Text('Retry'))],
      );
    } else if (s.model(s.interruptedId) case final m?) {
      content = (
        Icons.pause_circle_outline,
        'Download of ${m.name} stopped',
        'The app was closed before it finished',
        null,
        [TextButton(onPressed: () => retry(m), child: const Text('Resume'))],
      );
    } else {
      content = null;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: switch (content) {
        null => const SizedBox(width: double.infinity),
        (final icon, final title, final detail, final progress, final actions) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentMaxWidth + 64),
            child: Padding(
              padding: EdgeInsets.fromLTRB(context.screenPad, 0, context.screenPad, 8),
              child: Material(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => AiModelsPage.open(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: cs.onSecondaryContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: context.tt.titleSmall?.copyWith(color: cs.onSecondaryContainer)),
                                  if (detail != null)
                                    Text(detail, style: context.tt.bodySmall?.copyWith(color: cs.onSecondaryContainer)),
                                ],
                              ),
                            ),
                            ...actions,
                            if (downloading == null)
                              IconButton(
                                tooltip: 'Dismiss',
                                onPressed: ai.dismissNotices,
                                icon: Icon(Icons.close, size: 20, color: cs.onSecondaryContainer),
                              ),
                          ],
                        ),
                        if (downloading != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(36, 8, 12, 2),
                            child: LinearProgressIndicator(value: progress),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      },
    );
  }
}
