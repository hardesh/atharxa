import 'dart:convert';

import 'db.dart';
import '../app_clock.dart';

/// One saved assistant chat. Syncs between devices like everything else.
class Chat {
  Chat(this.row);
  final Map<String, Object?> row;

  String get id => row['id'] as String;
  String get title => row['title'] as String;
  DateTime get lastAt => DateTime.fromMillisecondsSinceEpoch((row['last_at'] as num).toInt());

  /// (fromUser, text) in order.
  List<(bool, String)> get messages => [
    for (final m in (jsonDecode(row['messages'] as String) as List).whereType<Map>())
      (m['u'] == true, m['t'] as String? ?? ''),
  ];
}

class ChatRepo {
  ChatRepo(this.db);
  final AppDb db;
  static const table = 'chats';

  /// Newest first.
  Future<List<Chat>> all() async => (await db.query(table, orderBy: 'last_at DESC')).map(Chat.new).toList();

  /// Creates (no [id]) or updates a chat; returns its id. The title is the
  /// first question, shortened.
  Future<String> save({String? id, required List<(bool, String)> messages}) {
    final first = messages.firstWhere((m) => m.$1, orElse: () => (true, 'Chat')).$2.trim();
    return db.save(table, {
      'id': ?id,
      'title': first.length > 60 ? '${first.substring(0, 57)}…' : first,
      'messages': jsonEncode([
        for (final (u, t) in messages) {'u': u, 't': t},
      ]),
      'last_at': AppClock.now().millisecondsSinceEpoch,
    });
  }

  Future<void> delete(String id) => db.delete(table, id);
}
