import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';
import 'data/db.dart';
import 'services/notification_service.dart';
import 'state/core_providers.dart';
import 'state/settings_providers.dart';
import 'sync/sync_service.dart';
import 'ui/shell.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/text_scale.dart';
import 'ui/widgets/app_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final db = await AppDb.open();
  final sync = SyncService(db, prefs);
  final notifications = NotificationService(prefs);
  runApp(
    ProviderScope(
      overrides: await appOverrides(db: db, prefs: prefs, sync: sync, notifications: notifications),
      child: const App(),
    ),
  );
  // Non-critical startup work runs after the first frame.
  await notifications.init();
  if (sync.enabled) await sync.start();
}

/// Injects the async-created singletons, plus synced settings preloaded so
/// the first frame already has the right theme. Also used by widget tests.
Future<List<Override>> appOverrides({
  required AppDb db,
  required SharedPreferences prefs,
  required SyncService sync,
  required NotificationService notifications,
}) async => [
  dbProvider.overrideWithValue(db),
  prefsProvider.overrideWithValue(prefs),
  syncServiceProvider.overrideWithValue(sync),
  notificationServiceProvider.overrideWithValue(notifications),
  initialSyncedSettingsProvider.overrideWithValue(await SyncedSettings.load(db)),
];

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(syncedSettingsProvider.select((s) => s.palette));
    final device = ref.watch(deviceSettingsProvider);
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(palette, Brightness.light),
      darkTheme: buildTheme(palette, Brightness.dark),
      themeMode: device.themeMode,
      builder: (context, child) => AppChrome.wrap(context, AppTextScale(factor: device.textScale, child: child!)),
      home: const AppShell(),
    );
  }
}
