import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_runtime.dart';
import '../app_info.dart';
import 'ai_controller.dart';

/// One message in the assistant chat.
@immutable
class ChatEntry {
  const ChatEntry({required this.fromUser, required this.text, this.done = true, this.error});
  final bool fromUser;
  final String text;

  /// False while the reply is still being written.
  final bool done;
  final String? error;

  ChatEntry copyWith({String? text, bool? done, String? error}) =>
      ChatEntry(fromUser: fromUser, text: text ?? this.text, done: done ?? this.done, error: error ?? this.error);
}

enum AssistantStatus { idle, loading, replying }

@immutable
class AssistantState {
  const AssistantState({this.messages = const [], this.status = AssistantStatus.idle, this.error});
  final List<ChatEntry> messages;
  final AssistantStatus status;

  /// Why the model could not load.
  final String? error;

  AssistantState copyWith({
    List<ChatEntry>? messages,
    AssistantStatus? status,
    String? error,
    bool clearError = false,
  }) => AssistantState(
    messages: messages ?? this.messages,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
  );
}

/// The assistant chat while its screen is open. Closing the screen ends the
/// conversation, and the model is freed a minute later.
final assistantProvider = NotifierProvider.autoDispose<AssistantController, AssistantState>(AssistantController.new);

class AssistantController extends Notifier<AssistantState> {
  AiConversation? _conversation;
  String? _conversationModel;

  static const _system =
      'You are ${AppInfo.assistantName}, the assistant in a personal app for food, water, workouts and money. '
      'Answer briefly and plainly. You cannot see the user\'s logged data yet, so never make up their numbers.';

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

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.status == AssistantStatus.replying) return;
    state = state.copyWith(
      status: AssistantStatus.replying,
      clearError: true,
      messages: [
        ...state.messages,
        ChatEntry(fromUser: true, text: q),
        const ChatEntry(fromUser: false, text: '', done: false),
      ],
    );
    final reply = StringBuffer();
    try {
      final model = await ref.read(aiProvider.notifier).ensureLoaded();
      if (_conversationModel != model.id) {
        await _conversation?.close();
        _conversation = await ref.read(aiRuntimeProvider).open(system: _system);
        _conversationModel = model.id;
      }
      await for (final token in _conversation!.send(q)) {
        if (!ref.mounted) return;
        reply.write(token);
        _updateLast((e) => e.copyWith(text: reply.toString()));
      }
      if (ref.mounted) _updateLast((e) => e.copyWith(done: true));
    } on Object catch (e) {
      if (ref.mounted) _updateLast((m) => m.copyWith(done: true, error: _message(e)));
    } finally {
      if (ref.mounted) state = state.copyWith(status: AssistantStatus.idle);
    }
  }

  Future<void> stop() async => _conversation?.stop();

  /// Clears the chat and starts a fresh conversation.
  Future<void> newChat() async {
    await _conversation?.close();
    _conversation = null;
    _conversationModel = null;
    state = const AssistantState();
  }

  void _updateLast(ChatEntry Function(ChatEntry) f) {
    final list = [...state.messages];
    list[list.length - 1] = f(list.last);
    state = state.copyWith(messages: list);
  }

  static String _message(Object e) => e is AiException ? e.message : 'The model stopped with an error: $e';
}
