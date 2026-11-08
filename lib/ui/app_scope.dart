import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/notification_service.dart';
import '../state/app_settings.dart';
import '../sync/sync_service.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.db,
    required this.settings,
    required this.sync,
    required this.notifications,
    required super.child,
  });

  final AppDb db;
  final AppSettings settings;
  final SyncService sync;
  final NotificationService notifications;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}

extension AppContext on BuildContext {
  AppDb get db => AppScope.of(this).db;
  AppSettings get settings => AppScope.of(this).settings;
}

/// Runs [load] and re-runs it whenever any of [tables] changes
/// (locally or because a sync brought in new rows).
class DbBuilder<T> extends StatefulWidget {
  const DbBuilder({super.key, required this.tables, required this.load, required this.builder, this.deps = const []});

  final List<String> tables;
  final Future<T> Function(AppDb db) load;
  final Widget Function(BuildContext context, T data) builder;

  /// Extra values (e.g. selected date) that trigger a reload when changed.
  final List<Object?> deps;

  @override
  State<DbBuilder<T>> createState() => _DbBuilderState<T>();
}

class _DbBuilderState<T> extends State<DbBuilder<T>> {
  StreamSubscription<String>? _sub;
  T? _data;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) {
      final db = context.db;
      _sub = db.changes.where(widget.tables.contains).listen((_) => _reload());
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant DbBuilder<T> old) {
    super.didUpdateWidget(old);
    if (old.deps.length != widget.deps.length ||
        Iterable.generate(widget.deps.length).any((i) => old.deps[i] != widget.deps[i])) {
      _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final d = await widget.load(context.db);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_data == null && null is! T) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}
