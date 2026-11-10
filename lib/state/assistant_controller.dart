import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_runtime.dart';
import '../ai/assistant_context.dart';
import '../app_info.dart';
import '../data/chat_repo.dart';
import '../data/food_repo.dart';
import '../data/models.dart';
import 'ai_controller.dart';
import 'core_providers.dart';
import 'settings_providers.dart';
import '../app_clock.dart';

/// One message in the assistant chat.
@immutable
class ChatEntry {
  const ChatEntry({
    required this.fromUser,
    required this.text,
    this.done = true,
    this.error,
    this.reads = const [],
    this.foods = const [],
  });
  final bool fromUser;
  final String text;

  /// False while the reply is still being written.
  final bool done;
  final String? error;

  /// The data the answer could draw on ("Today’s log", "My foods").
  final List<String> reads;

  /// Foods from My foods the answer suggests, offered as "Add to …".
  final List<FoodItem> foods;

  ChatEntry copyWith({String? text, bool? done, String? error, List<String>? reads, List<FoodItem>? foods}) =>
      ChatEntry(
        fromUser: fromUser,
        text: text ?? this.text,
        done: done ?? this.done,
        error: error ?? this.error,
        reads: reads ?? this.reads,
        foods: foods ?? this.foods,
      );
}

enum AssistantStatus { idle, loading, replying }

@immutable
class AssistantState {
  const AssistantState({this.chatId, this.messages = const [], this.status = AssistantStatus.idle, this.error});

  /// The saved chat these messages belong to (null until the first reply).
  final String? chatId;
  final List<ChatEntry> messages;
  final AssistantStatus status;

  /// Why the model could not load.
  final String? error;

  AssistantState copyWith({
    String? chatId,
    List<ChatEntry>? messages,
    AssistantStatus? status,
    String? error,
    bool clearError = false,
  }) => AssistantState(
    chatId: chatId ?? this.chatId,
    messages: messages ?? this.messages,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
  );
}

/// The assistant chat while its screen is open. Every answered turn is saved
/// (chats sync like other data); closing the screen ends the model
/// conversation, and the model is freed a minute later.
final assistantProvider = NotifierProvider.autoDispose<AssistantController, AssistantState>(AssistantController.new);

/// Saved chats, newest first (history list).
final chatsProvider = FutureProvider.autoDispose<List<ChatSummary>>((ref) {
  ref.watchTables(const [ChatRepo.table]);
  return ChatRepo(ref.watch(dbProvider)).all();
});

class AssistantController extends Notifier<AssistantState> {
  AiConversation? _conversation;
  String? _conversationModel;
  List<String> _reads = const [];

  /// My foods, read once per conversation to spot foods an answer names.
  List<FoodItem> _mine = const [];

  @override
  AssistantState build() {
    final ai = ref.read(aiProvider.notifier);
    ref.onDispose(() {
      _conversation?.close();
      ai.releaseSoon();
    });
    return const AssistantState();
  }

  /// Loads the active model ahead of the first message.
  Future<void> prepare() async {
    if (ref.read(aiProvider).active == null) return;
    state = state.copyWith(status: AssistantStatus.loading, clearError: true);
    try {
      await ref.read(aiProvider.notifier).ensureLoaded();
      if (ref.mounted) state = state.copyWith(status: AssistantStatus.idle);
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(status: AssistantStatus.idle, error: _message(e));
    }
  }

  /// The user's data (in the scopes they allow) plus earlier turns of this
  /// chat, for a new model conversation.
  Future<String> _instructions(List<ChatEntry> earlier) async {
    final ai = ref.read(aiProvider);
    final settings = ref.read(syncedSettingsProvider);
    final ctx = ai.scopes.isEmpty
        ? AssistantContext.empty
        : await buildAssistantContext(
            ref.read(dbProvider),
            scopes: ai.scopes,
            goals: settings.goals,
            currency: settings.currency,
          );
    _reads = ctx.reads;
    return assistantInstructions(
      AppInfo.assistantName,
      ctx,
      earlier: [
        for (final m in earlier)
          if (m.error == null && m.text.isNotEmpty) (m.fromUser, m.text),
      ],
    );
  }

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.status == AssistantStatus.replying) return;
    final earlier = state.messages;
    state = state.copyWith(
      status: AssistantStatus.replying,
      clearError: true,
      messages: [
        ...earlier,
        ChatEntry(fromUser: true, text: q),
        ChatEntry(fromUser: false, text: '', done: false, reads: _reads),
      ],
    );
    final reply = StringBuffer();
    try {
      final model = await ref.read(aiProvider.notifier).ensureLoaded();
      if (_conversationModel != model.id) {
        await _conversation?.close();
        _conversation = await ref.read(aiRuntimeProvider).open(system: await _instructions(earlier));
        _mine = ref.read(aiProvider).scopes.contains(AiScope.food)
            ? await FoodRepo(ref.read(dbProvider)).myFoods()
            : const [];
        _conversationModel = model.id;
        _updateLast((e) => e.copyWith(reads: _reads));
      }
      await for (final token in _conversation!.send(q)) {
        if (!ref.mounted) return;
        reply.write(token);
        _updateLast((e) => e.copyWith(text: reply.toString()));
      }
      if (!ref.mounted) return;
      _updateLast((e) => e.copyWith(done: true, foods: foodsMentioned(reply.toString(), _mine)));
      await _save();
    } on Object catch (e) {
      if (ref.mounted) _updateLast((m) => m.copyWith(done: true, error: _message(e)));
    } finally {
      if (ref.mounted) state = state.copyWith(status: AssistantStatus.idle);
    }
  }

  Future<void> _save() async {
    final id = await ChatRepo(ref.read(dbProvider)).save(
      id: state.chatId,
      messages: [
        for (final m in state.messages)
          if (m.error == null) (m.fromUser, m.text),
      ],
    );
    if (ref.mounted) state = state.copyWith(chatId: id);
  }

  Future<void> stop() async => _conversation?.stop();

  /// Clears the chat and starts a fresh conversation.
  Future<void> newChat() async {
    await _endConversation();
    state = const AssistantState();
  }

  /// Shows a saved chat; the next question continues it.
  Future<void> openChat(String id) async {
    await _endConversation();
    final c = await ChatRepo(ref.read(dbProvider)).get(id);
    if (c == null || !ref.mounted) return;
    state = AssistantState(
      chatId: c.id,
      messages: [for (final (u, t) in c.messages) ChatEntry(fromUser: u, text: t)],
    );
  }

  Future<void> deleteChat(String id) async {
    await ChatRepo(ref.read(dbProvider)).delete(id);
    if (state.chatId == id) await newChat();
  }

  /// Logs [food] (its serving, else 100 g) to [meal] today; returns the
  /// entry id for Undo.
  Future<String> addFood(FoodItem food, Meal meal) => FoodRepo(
    ref.read(dbProvider),
  ).add(FoodRepo.logs, day: dayKey(AppClock.now()), meal: meal, food: food, grams: food.servingG ?? 100);

  Future<void> _endConversation() async {
    await _conversation?.close();
    _conversation = null;
    _conversationModel = null;
  }

  void _updateLast(ChatEntry Function(ChatEntry) f) {
    final list = [...state.messages];
    list[list.length - 1] = f(list.last);
    state = state.copyWith(messages: list);
  }

  static String _message(Object e) => e is AiException ? e.message : 'The model stopped with an error: $e';
}
