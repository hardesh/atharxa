import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_models.dart';
import '../../../ai/ai_runtime.dart';
import '../../../ai/assistant_context.dart';
import '../../../services/file_saver.dart';
import '../../../state/ai_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../widgets/tag.dart';

/// "this phone" / "This Mac", for the device [caps] describes (this
/// platform's kind until it has been read).
String deviceNoun(DeviceCapabilities? caps, {bool capital = false}) {
  final desktop = caps?.desktop ?? !(Platform.isAndroid || Platform.isIOS);
  final n = !desktop ? 'phone' : (Platform.isMacOS ? 'Mac' : 'computer');
  return '${capital ? 'This' : 'this'} $n';
}

/// You › AI models (DESIGN.md §7.6): what this device can run, installed
/// models (pick the one chats use), models to download, import a file.
/// Models are per device and never sync.
class AiModelsPage extends ConsumerStatefulWidget {
  const AiModelsPage({super.key});

  /// Pushed from the assistant's model picker.
  static Future<void> open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('AI models')),
        body: const AiModelsPage(),
      ),
    ),
  );

  @override
  ConsumerState<AiModelsPage> createState() => _AiModelsPageState();
}

class _AiModelsPageState extends ConsumerState<AiModelsPage> {
  @override
  void initState() {
    super.initState();
    ref.read(aiProvider.notifier).refresh();
  }

  Future<void> _download(AiModel m) async {
    final why = await ref.read(aiProvider.notifier).download(m);
    if (why != null && mounted) showMessage(context, why);
  }

  Future<void> _remove(AiModel m) async {
    final ok = await confirm(
      context,
      title: 'Remove ${m.name}?',
      message: 'Frees ${fmtSize(m.sizeBytes)}. You can download it again later.',
      confirmLabel: 'Remove',
    );
    if (ok) await ref.read(aiProvider.notifier).remove(m);
  }

  Future<void> _import() async {
    final path = await pickFilePath(const ['gguf', 'litertlm']);
    if (path == null || !mounted) return;
    showMessage(context, 'Copying the model file…');
    try {
      final m = await ref.read(aiProvider.notifier).import(path);
      if (mounted) showMessage(context, 'Added ${m.name}');
    } on AiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } on FileSystemException catch (e) {
      if (mounted) showMessage(context, 'Could not copy the file: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(aiProvider);
    final caps = s.caps;
    final recommended = caps == null ? null : recommendedFor(caps);
    final active = s.active;
    return PageBody(
      children: [
        AppCard(
          child: Row(
            children: [
              Icon(caps?.desktop ?? Platform.isMacOS ? Icons.laptop_mac : Icons.smartphone, color: context.cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceNoun(caps, capital: true), style: context.tt.titleMedium),
                    Text(
                      caps == null
                          ? 'Checking…'
                          : [
                              if (caps.ramGb != null) '${caps.ramGb} GB RAM',
                              ?caps.chip,
                              if (caps.freeBytes != null) '${fmtSize(caps.freeBytes!)} free',
                            ].join(' · '),
                      style: context.tt.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (s.installedModels.isNotEmpty)
          _Section(
            title: 'Installed',
            subtitle: 'The selected model answers in the assistant',
            children: [
              RadioGroup<String>(
                groupValue: active?.id,
                onChanged: (id) {
                  final m = s.installedModels.where((m) => m.id == id).firstOrNull;
                  if (m != null) ref.read(aiProvider.notifier).choose(m);
                },
                child: Column(
                  children: [
                    for (final m in s.installedModels)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Radio<String>(value: m.id),
                        title: Text(m.name),
                        subtitle: Text(
                          [
                            fmtSize(m.sizeBytes),
                            if (m.family != AiFamily.other) m.family.maker,
                            if (s.loadedId == m.id && s.backend != null) 'running on the ${s.backend!.label}',
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _remove(m),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        onTap: () => ref.read(aiProvider.notifier).choose(m),
                      ),
                  ],
                ),
              ),
            ],
          ),
        _Section(
          title: 'Available',
          subtitle: 'Downloaded once, then used offline',
          children: [
            if (!s.ready) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            for (final m in s.available)
              _AvailableTile(
                model: m,
                fit: caps == null ? AiFit.fits : fitFor(m, caps),
                recommended: m.id == recommended?.id,
                device: deviceNoun(caps),
                progress: s.downloads[m.id],
                error: s.errors[m.id],
                onDownload: () => _download(m),
                onCancel: () => ref.read(aiProvider.notifier).cancelDownload(m),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Download on Wi-Fi only'),
              subtitle: const Text('Models are large (1–7 GB)'),
              value: s.wifiOnly,
              onChanged: (v) => ref.read(aiProvider.notifier).setWifiOnly(v),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Import a model file…'),
              ),
            ),
          ],
        ),
        _Section(
          title: 'What the assistant can read',
          subtitle: 'It reads on ${deviceNoun(caps)} only; nothing leaves it',
          children: [
            for (final scope in AiScope.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(scope.label),
                subtitle: Text(scope.detail),
                value: s.scopes.contains(scope),
                onChanged: (v) => ref.read(aiProvider.notifier).setScope(scope, v),
              ),
          ],
        ),
        Text(
          'Models run entirely on ${deviceNoun(caps)} and are not synced: each device downloads the ones it can '
          'run. Gemma 4 models are by Google, Qwen3.5 by Alibaba; both under the Apache 2.0 licence.',
          style: context.tt.bodySmall,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.subtitle, required this.children});
  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.tt.titleMedium),
        Text(subtitle, style: context.tt.bodySmall),
        const SizedBox(height: 4),
        ...children,
      ],
    ),
  );
}

class _AvailableTile extends StatelessWidget {
  const _AvailableTile({
    required this.model,
    required this.fit,
    required this.recommended,
    required this.device,
    required this.progress,
    required this.error,
    required this.onDownload,
    required this.onCancel,
  });

  final AiModel model;
  final AiFit fit;
  final bool recommended;

  /// "this phone".
  final String device;
  final double? progress;
  final String? error;
  final VoidCallback onDownload, onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (tag, tagFg, tagBg) = switch (fit) {
      _ when recommended => ('Recommended', cs.onPrimaryContainer, cs.primaryContainer),
      AiFit.fits => ('Fits $device', null, null),
      AiFit.tight => ('May be slow here', null, null),
      AiFit.tooLarge => ('Too large for $device', cs.outline, null),
      AiFit.desktopOnly => ('Mac only', cs.outline, null),
      AiFit.otherChip || AiFit.retired => ('', null, null),
    };
    final canRun = fit == AiFit.fits || fit == AiFit.tight;
    final p = progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name, style: context.tt.bodyLarge),
                    Text('${fmtSize(model.sizeBytes)} · ${model.note}', style: context.tt.bodySmall),
                    const SizedBox(height: 4),
                    Tag(tag, fg: tagFg, bg: tagBg, small: true),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (p != null)
                IconButton(tooltip: 'Cancel download', onPressed: onCancel, icon: const Icon(Icons.close))
              else
                IconButton(
                  tooltip: 'Download ${model.name}',
                  onPressed: canRun ? onDownload : null,
                  icon: const Icon(Icons.download_outlined),
                ),
            ],
          ),
          if (p != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: p == 0 ? null : p),
            const SizedBox(height: 2),
            Text(
              p >= 0.995 ? 'Checking the file…' : 'Downloading · ${(p * 100).floor()} %',
              style: context.tt.bodySmall,
            ),
          ],
          if (error != null) Text(error!, style: context.tt.bodySmall?.copyWith(color: cs.error)),
        ],
      ),
    );
  }
}
