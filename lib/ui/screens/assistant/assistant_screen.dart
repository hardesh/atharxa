import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ai/ai_models.dart';
import '../../../app_info.dart';
import '../../../data/food_repo.dart';
import '../../../data/models.dart';
import '../../../state/ai_controller.dart';
import '../../../state/core_providers.dart';
import '../../../state/assistant_controller.dart';
import '../../format.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';
import '../../widgets/layout.dart';
import '../../widgets/meal_card.dart';
import '../you/ai_models_page.dart';

/// Opens the assistant (AI button in every top bar, ⌘K on the Mac); [ask]
/// is sent as soon as the model is ready ("Summarize month").
Future<void> openAssistant(BuildContext context, {String? ask}) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AssistantScreen(ask: ask)));

/// Assistant chat (DESIGN.md §5, Assistant.dc.html): runs on this device with
/// the model chosen in AI models; picker in the header.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key, this.ask});

  /// A question to send on opening.
  final String? ask;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'Suggest a high-protein dinner from my foods',
    'How am I doing today?',
    'Summarize my week',
    'Where did my money go this month?',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(aiProvider.notifier).refresh();
      await ref.read(assistantProvider.notifier).prepare();
      final ask = widget.ask;
      if (ask != null && mounted && ref.read(aiProvider).active != null) _send(ask);
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
            if (active != null && !context.isRoomy)
              IconButton(
                tooltip: 'Chat history',
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (sheet) => SizedBox(
                    height: MediaQuery.sizeOf(sheet).height * 0.7,
                    child: _ChatHistory(onOpened: () => Navigator.pop(sheet)),
                  ),
                ),
                icon: const Icon(Icons.history),
              ),
            IconButton(
              tooltip: 'New chat',
              onPressed: chat.messages.isEmpty ? null : () => ref.read(assistantProvider.notifier).newChat(),
              icon: const Icon(Icons.add_comment_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _withHistory(
          context,
          showHistory: ai.ready && active != null,
          child: !ai.ready
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
                              itemBuilder: (_, i) => _Bubble(
                                entry: chat.messages[i],
                                onTryAnother: () => _send('Suggest something different.'),
                              ),
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
      ),
    );
  }

  /// Wide screens keep the chat list on the left (DESIGN: Mac keeps a
  /// chat-history list); phones open it from the header.
  Widget _withHistory(BuildContext context, {required bool showHistory, required Widget child}) {
    if (!showHistory || !context.isRoomy) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: _ChatHistory(onOpened: () {})),
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ],
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
    final backend = state.loadedId == active.id ? state.backend?.label : null;
    final where = backend == null || active.name.endsWith(backend) ? '' : ' · $backend';
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
      // Capped so the header's other buttons always fit on a narrow phone.
      builder: (context, ctl, _) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
        child: TextButton.icon(
          onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text('${active.name}$where', overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.entry, required this.onTryAnother});
  final ChatEntry entry;
  final VoidCallback onTryAnother;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              if (!user && entry.reads.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.visibility_outlined, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Read ${entry.reads.join(' · ')}',
                          style: context.tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              if (text.isEmpty && !entry.done)
                const SizedBox(width: 32, height: 16, child: LinearProgressIndicator())
              else
                SelectableText(
                  text,
                  style: context.tt.bodyLarge?.copyWith(color: user ? cs.onPrimaryContainer : cs.onSurface),
                ),
              if (entry.error != null) Text(entry.error!, style: context.tt.bodySmall?.copyWith(color: cs.error)),
              if (entry.foods.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in entry.foods) _AddFoodChip(food: f),
                    ActionChip(
                      avatar: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try another'),
                      onPressed: onTryAnother,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Add Paneer bhurji to Dinner · 150 g · 330 kcal": logs a suggested food
/// (its serving, else 100 g) to the meal for the time of day, with Undo.
class _AddFoodChip extends ConsumerWidget {
  const _AddFoodChip({required this.food});
  final FoodItem food;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meal = mealForNow();
    final g = food.servingG ?? 100;
    return ActionChip(
      avatar: const Icon(Icons.add, size: 18),
      label: Text('Add ${food.name} to ${meal.label} · ${fmtGrams(g)} g · ${fmtInt(food.per100g.kcal * g / 100)} kcal'),
      onPressed: () async {
        final id = await ref.read(assistantProvider.notifier).addFood(food, meal);
        if (!context.mounted) return;
        showUndo(context, 'Added ${food.name} to ${meal.label}', () => FoodRepo(context.db).remove(FoodRepo.logs, id));
      },
    );
  }
}

/// Saved chats, newest first: tap to continue one, or delete it.
class _ChatHistory extends ConsumerWidget {
  const _ChatHistory({required this.onOpened});
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider).value ?? const [];
    final current = ref.watch(assistantProvider.select((s) => s.chatId));
    final ctl = ref.read(assistantProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: FilledButton.tonalIcon(
            onPressed: () {
              ctl.newChat();
              onOpened();
            },
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('New chat'),
          ),
        ),
        Expanded(
          child: chats.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Your chats appear here.', style: context.tt.bodySmall, textAlign: TextAlign.center),
                )
              : ListView(
                  children: [
                    for (final c in chats)
                      ListTile(
                        selected: c.id == current,
                        title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(fmtWhen(c.lastAt)),
                        trailing: IconButton(
                          tooltip: 'Delete chat',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              title: 'Delete this chat?',
                              message: 'It is removed from your other devices too.',
                              confirmLabel: 'Delete',
                            );
                            if (ok) await ctl.deleteChat(c.id);
                          },
                        ),
                        onTap: () {
                          ctl.openChat(c);
                          onOpened();
                        },
                      ),
                  ],
                ),
        ),
      ],
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
