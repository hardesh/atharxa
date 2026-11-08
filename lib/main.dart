import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/db.dart';
import 'services/notification_service.dart';
import 'state/app_settings.dart';
import 'sync/sync_service.dart';
import 'ui/app_scope.dart';
import 'ui/shell.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/text_scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final db = await AppDb.open();
  final settings = await AppSettings.load(db, prefs);
  final sync = SyncService(db, prefs);
  final notifications = NotificationService(prefs);
  runApp(AtharxaApp(db: db, settings: settings, sync: sync, notifications: notifications));
  // Non-critical startup work runs after the first frame.
  await notifications.init();
  if (sync.enabled) await sync.start();
}

class AtharxaApp extends StatelessWidget {
  const AtharxaApp({
    super.key,
    required this.db,
    required this.settings,
    required this.sync,
    required this.notifications,
  });

  final AppDb db;
  final AppSettings settings;
  final SyncService sync;
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      db: db,
      settings: settings,
      sync: sync,
      notifications: notifications,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'Atharxa',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(settings.palette, Brightness.light),
          darkTheme: buildTheme(settings.palette, Brightness.dark),
          themeMode: settings.themeMode,
          builder: (context, child) => AppTextScale(factor: settings.textScale, child: child!),
          home: const AppShell(),
        ),
      ),
    );
  }
}
