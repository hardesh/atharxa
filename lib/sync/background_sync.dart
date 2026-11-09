import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db.dart';
import 'peers.dart';
import 'sync_auth.dart';
import 'sync_protocol.dart';

/// Android background sync: every 15 minutes (the OS minimum), on unmetered
/// Wi-Fi, run one session with each paired device. On macOS the app keeps
/// running with its window closed, so the in-app timers cover it.
class BackgroundSync {
  static const _uniqueName = 'app-wifi-sync';
  static bool _initialized = false;

  static Future<void> schedule() async {
    if (!Platform.isAndroid) return;
    if (!_initialized) {
      await Workmanager().initialize(backgroundSyncDispatcher);
      _initialized = true;
    }
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      'sync',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.unmetered),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    // A job scheduled by an earlier run survives restarts: initialize so it
    // can be cancelled.
    if (!_initialized) {
      await Workmanager().initialize(backgroundSyncDispatcher);
      _initialized = true;
    }
    await Workmanager().cancelByUniqueName(_uniqueName);
  }
}

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = SyncPrefs(await SharedPreferences.getInstance());
    if (!prefs.enabled || !prefs.autoSync || !SyncAuth.isValidCode(prefs.code) || prefs.peers.isEmpty) return true;
    final db = await AppDb.open(separateConnection: true);
    final client = SyncClient(db: db, auth: SyncAuth(prefs.code), deviceName: prefs.deviceName);
    try {
      for (final p in prefs.peers) {
        try {
          final r = await client.syncWith(p.address);
          await prefs.recordSession(
            peerId: r.peerId,
            peerName: r.peerName,
            host: p.host,
            port: p.port,
            sent: r.sent,
            received: r.received,
          );
        } on SyncException {
          // Try again next run.
        }
      }
    } finally {
      client.close();
      await db.close();
    }
    return true;
  });
}
