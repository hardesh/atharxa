import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_models.dart';
import '../../../app_info.dart';
import '../../../state/ai_controller.dart';
import '../../../state/assistant_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../you/ai_models_page.dart';

/// Opens the assistant (AI button in every top bar, ⌘K on the Mac).
Future<void> openAssistant(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AssistantScreen()));

/// Assistant chat (DESIGN.md §5, Assistant.dc.html): runs on this device with
/// the model chosen in AI models; picker in the header.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'Suggest a high-protein vegetarian dinner',
    'How much water should I drink in a day?',
    'Give me a 20-minute home workout',
    'Tips to stick to a monthly budget',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(aiProvider.notifier).refresh();
      await ref.read(assistantProvider.notifier).prepare();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = text ?? _input.text;
    if (q.trim().isEmpty) return;
    _input.clear();
    ref.read(assistantProvider.notifier).send(q);
  }

  Future<void> _switchTo(AiModel m) async {
    await ref.read(aiProvider.notifier).choose(m);
    final chat = ref.read(assistantProvider.notifier);
    await chat.newChat();
    await chat.prepare();
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiProvider);
    final chat = ref.watch(assistantProvider);
    // Keep the newest text in view while a reply streams in.
    ref.listen(assistantProvider.select((s) => s.messages), (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });
    final active = ai.active;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppInfo.assistantName),
          actions: [
            if (active != null) _ModelPicker(state: ai, onPick: _switchTo),
            IconButton(
              tooltip: 'New chat',
              onPressed: chat.messages.isEmpty ? null : () => ref.read(assistantProvider.notifier).newChat(),
              icon: const Icon(Icons.add_comment_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: !ai.ready
            ? const Center(child: CircularProgressIndicator())
            : active == null
            ? _SetUp(state: ai)
            : Column(
                children: [
                  if (chat.status == AssistantStatus.loading) ...[
                    const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('Loading ${active.name}…', style: context.tt.bodySmall),
                    ),
                  ],
                  if (chat.error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(chat.error!, style: context.tt.bodyMedium?.copyWith(color: context.cs.error)),
                    ),
                  Expanded(
                    child: chat.messages.isEmpty
                        ? EmptyState(
                            icon: Icons.auto_awesome,
                            title: 'Ask anything',
                            message: 'Food ideas, workouts, budgeting — answered on ${deviceNoun(ai.caps)}, offline.',
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: EdgeInsets.symmetric(horizontal: context.screenPad, vertical: 16),
                            itemCount: chat.messages.length,
                            itemBuilder: (_, i) => _Bubble(entry: chat.messages[i]),
                          ),
                  ),
                  if (chat.messages.isEmpty)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: context.screenPad),
                        children: [
                          for (final s in _suggestions)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(label: Text(s), onPressed: () => _send(s)),
                            ),
                        ],
                      ),
                    ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(context.screenPad, 8, context.screenPad, 4),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _input,
                                      minLines: 1,
                                      maxLines: 5,
                                      textInputAction: TextInputAction.send,
                                      onSubmitted: (_) => _send(),
                                      decoration: const InputDecoration(hintText: 'Message'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (chat.status == AssistantStatus.replying)
                                    IconButton.filledTonal(
                                      tooltip: 'Stop',
                                      onPressed: () => ref.read(assistantProvider.notifier).stop(),
                                      icon: const Icon(Icons.stop),
                                    )
                                  else
                                    IconButton.filled(
                                      tooltip: 'Send',
                                      onPressed: chat.status == AssistantStatus.loading ? null : _send,
                                      icon: const Icon(Icons.arrow_upward),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Runs on ${deviceNoun(ai.caps)}, offline. Answers can be wrong.',
                                style: context.tt.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Header chip: the model in use; menu to switch or manage models.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.state, required this.onPick});
  final AiState state;
  final ValueChanged<AiModel> onPick;

  @override
  Widget build(BuildContext context) {
    final active = state.active!;
    final where = state.loadedId == active.id && state.backend != null ? ' · ${state.backend!.label}' : '';
    return MenuAnchor(
      menuChildren: [
        for (final m in state.installedModels)
          MenuItemButton(
            leadingIcon: Icon(m.id == active.id ? Icons.check : null),
            onPressed: m.id == active.id ? null : () => onPick(m),
            child: Text('${m.name} · ${fmtSize(m.sizeBytes)}'),
          ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.tune),
          onPressed: () => AiModelsPage.open(context),
          child: const Text('Manage models…'),
        ),
      ],
      builder: (context, ctl, _) => TextButton.icon(
        onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
        icon: const Icon(Icons.expand_more, size: 18),
        label: Text('${active.name}$where', overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry});
  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final user = entry.fromUser;
    final text = entry.text;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: user ? 520 : contentMaxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: user ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10) : EdgeInsets.zero,
          decoration: user ? BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(18)) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isEmpty && !entry.done)
                const SizedBox(width: 32, height: 16, child: LinearProgressIndicator())
              else
                SelectableText(
                  text,
                  style: context.tt.bodyLarge?.copyWith(color: user ? cs.onPrimaryContainer : cs.onSurface),
                ),
              if (entry.error != null) Text(entry.error!, style: context.tt.bodySmall?.copyWith(color: cs.error)),
            ],
          ),
        ),
      ),
    );
  }
}

/// No model yet: offer this device's recommended one, or the full list.
class _SetUp extends ConsumerWidget {
  const _SetUp({required this.state});
  final AiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = state.caps;
    final m = caps == null ? null : recommendedFor(caps);
    final p = m == null ? null : state.downloads[m.id];
    return EmptyState(
      icon: Icons.auto_awesome,
      title: 'Set up the assistant',
      message:
          'It runs entirely on ${deviceNoun(state.caps)}: download a model once, then chat offline. '
          'Nothing you ask leaves the device.',
      action: Column(
        children: [
          if (m != null && p == null)
            FilledButton.icon(
              onPressed: () async {
                final why = await ref.read(aiProvider.notifier).download(m);
                if (why != null && context.mounted) showMessage(context, why);
              },
              icon: const Icon(Icons.download_outlined),
              label: Text('Download ${m.name} · ${fmtSize(m.sizeBytes)}'),
            ),
          if (p != null) ...[
            SizedBox(width: 280, child: LinearProgressIndicator(value: p == 0 ? null : p)),
            const SizedBox(height: 6),
            Text(
              p >= 0.995 ? 'Checking the file…' : 'Downloading ${m!.name} · ${(p * 100).floor()} %',
              style: context.tt.bodySmall,
            ),
          ],
          if (m != null && state.errors[m.id] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(state.errors[m.id]!, style: context.tt.bodySmall?.copyWith(color: context.cs.error)),
            ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => AiModelsPage.open(context), child: const Text('Choose another model')),
        ],
      ),
    );
  }
}
