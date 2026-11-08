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
    if (!Platform.isAndroid || !_initialized) return;
    await Workmanager().cancelByUniqueName(_uniqueName);
  }

  /// One pass with every paired peer. Returns peers with updated stats.
  static Future<List<PairedPeer>> runOnce(AppDb db, SyncPrefs prefs) async {
    final client = SyncClient(db: db, auth: SyncAuth(prefs.code), name: prefs.deviceName ?? 'Android phone');
    final updated = <PairedPeer>[];
    try {
      for (final p in prefs.peers) {
        try {
          final r = await client.syncWith(p.address);
          updated.add(
            p.copyWith(name: r.peerName, lastSyncAt: DateTime.now(), lastSent: r.sent, lastReceived: r.received),
          );
        } on SyncException {
          updated.add(p);
        }
      }
    } finally {
      client.close();
    }
    return updated;
  }
}

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = SyncPrefs(await SharedPreferences.getInstance());
    if (!prefs.enabled || !prefs.autoSync || !SyncAuth.isValidCode(prefs.code) || prefs.peers.isEmpty) return true;
    final db = await AppDb.open();
    try {
      await prefs.setPeers(await BackgroundSync.runOnce(db, prefs));
    } finally {
      await db.close();
    }
    return true;
  });
}
