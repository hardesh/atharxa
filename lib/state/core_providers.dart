import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../services/notification_service.dart';
import '../sync/sync_service.dart';

/// Opened in `main` (async) and injected with `overrideWithValue`.
final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError('dbProvider must be overridden'));
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);
final syncServiceProvider = Provider<SyncService>(
  (ref) => throw UnimplementedError('syncServiceProvider must be overridden'),
);
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('notificationServiceProvider must be overridden'),
);

/// A counter that ticks whenever [table] changes — from a local edit or rows
/// arriving via Wi-Fi sync. Data providers `watch` it to re-query.
final tableVersionProvider = NotifierProvider.family<TableVersion, int, String>(TableVersion.new);

class TableVersion extends Notifier<int> {
  TableVersion(this.table);
  final String table;

  @override
  int build() {
    final sub = ref.watch(dbProvider).changes.where((t) => t == table).listen((_) => state++);
    ref.onDispose(sub.cancel);
    return 0;
  }
}

extension WatchTables on Ref {
  /// Re-runs the calling provider when any of [tables] changes.
  void watchTables(Iterable<String> tables) {
    for (final t in tables) {
      watch(tableVersionProvider(t));
    }
  }
}

/// Imperative access from callbacks (tap handlers, dialogs) where no `ref` is
/// at hand. Widgets that render data should `ref.watch` providers instead.
extension ProviderContext on BuildContext {
  T readProvider<T>(ProviderListenable<T> p) => ProviderScope.containerOf(this, listen: false).read(p);
  AppDb get db => readProvider(dbProvider);
}
