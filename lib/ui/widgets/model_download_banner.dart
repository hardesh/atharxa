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

/// The last step of a download is checking the file (the engine reports
/// 99 % until then).
bool isCheckingDownload(double progress) => progress >= 0.99;

/// "61 % · 1.6 GB of 2.6 GB".
String downloadProgress(AiModel m, double progress) =>
    '${(progress * 100).floor()} % · ${fmtSize((m.sizeBytes * progress).round())} of ${fmtSize(m.sizeBytes)}';

/// "Downloading · 61 % · 1.6 GB of 2.6 GB", or "Checking the file…".
String downloadStatus(AiModel m, double progress) =>
    isCheckingDownload(progress) ? 'Checking the file…' : 'Downloading · ${downloadProgress(m, progress)}';

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

    Future<void> retry(AiModel m) async {
      final why = await ai.download(m);
      if (why != null && context.mounted) showMessage(context, why);
    }

    final downloading = s.downloads.entries.firstOrNull;
    final notice = s.notice;
    final banner = switch ((downloading, notice)) {
      (MapEntry(key: final id, value: final p), _) when s.model(id) != null => _Banner(
        icon: Icons.downloading,
        title: '${isCheckingDownload(p) ? 'Checking' : 'Downloading'} ${s.model(id)!.name}',
        detail: isCheckingDownload(p)
            ? 'Making sure the file is complete'
            : '${downloadProgress(s.model(id)!, p)} · keeps going in the background',
        progress: p == 0 || isCheckingDownload(p) ? null : p,
        showProgress: true,
        action: isCheckingDownload(p)
            ? null
            : TextButton(
                onPressed: () async {
                  final m = s.model(id)!;
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
      ),
      (_, ModelReady(:final modelId)) when s.model(modelId) != null => _Banner(
        icon: Icons.check_circle_outline,
        title: '${s.model(modelId)!.name} is ready',
        detail: 'The assistant now runs on ${deviceNoun(s.caps)}, offline',
        action: TextButton(
          onPressed: () {
            ai.dismissNotices();
            openAssistant(context);
          },
          child: const Text('Open assistant'),
        ),
        onDismiss: ai.dismissNotices,
      ),
      (_, DownloadFailed(:final modelId, :final message)) when s.model(modelId) != null => _Banner(
        icon: Icons.error_outline,
        title: 'Couldn’t download ${s.model(modelId)!.name}',
        detail: message,
        action: TextButton(onPressed: () => retry(s.model(modelId)!), child: const Text('Retry')),
        onDismiss: ai.dismissNotices,
      ),
      (_, DownloadStopped(:final modelId)) when s.model(modelId) != null => _Banner(
        icon: Icons.pause_circle_outline,
        title: 'Download of ${s.model(modelId)!.name} stopped',
        detail: 'The app was closed before it finished',
        action: TextButton(onPressed: () => retry(s.model(modelId)!), child: const Text('Resume')),
        onDismiss: ai.dismissNotices,
      ),
      _ => null,
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: banner ?? const SizedBox(width: double.infinity),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.title,
    required this.detail,
    this.progress,
    this.showProgress = false,
    this.action,
    this.onDismiss,
  });

  final IconData icon;
  final String title, detail;

  /// Null with [showProgress]: an indeterminate bar.
  final double? progress;
  final bool showProgress;
  final Widget? action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final fg = context.cs.onSecondaryContainer;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMaxWidth + 64),
        child: Padding(
          padding: EdgeInsets.fromLTRB(context.screenPad, 0, context.screenPad, 8),
          child: Material(
            color: context.cs.secondaryContainer,
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
                        Icon(icon, color: fg),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: context.tt.titleSmall?.copyWith(color: fg)),
                              Text(detail, style: context.tt.bodySmall?.copyWith(color: fg)),
                            ],
                          ),
                        ),
                        ?action,
                        if (onDismiss != null)
                          IconButton(
                            tooltip: 'Dismiss',
                            onPressed: onDismiss,
                            icon: Icon(Icons.close, size: 20, color: fg),
                          ),
                      ],
                    ),
                    if (showProgress)
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
    );
  }
}
