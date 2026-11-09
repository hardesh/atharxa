import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// A device this one has synced with (stored per device, never synced).
class PairedPeer {
  const PairedPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.lastSyncAt,
    this.lastSent = 0,
    this.lastReceived = 0,
  });

  final String id, name, host;
  final int port;
  final DateTime? lastSyncAt;
  final int lastSent, lastReceived;

  String get address => '$host:$port';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'at': lastSyncAt?.millisecondsSinceEpoch,
    'sent': lastSent,
    'received': lastReceived,
  };

  static PairedPeer fromJson(Map<String, dynamic> j) => PairedPeer(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as String,
    port: (j['port'] as num).toInt(),
    lastSyncAt: j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    lastSent: (j['sent'] as num?)?.toInt() ?? 0,
    lastReceived: (j['received'] as num?)?.toInt() ?? 0,
  );
}

/// Per-device sync settings in SharedPreferences.
class SyncPrefs {
  SyncPrefs(this.prefs);
  final SharedPreferences prefs;

  static const _enabled = 'sync_enabled', _code = 'sync_code', _name = 'device_name';
  static const _auto = 'sync_auto', _interval = 'sync_interval_min', _peers = 'sync_peers';

  bool get enabled => prefs.getBool(_enabled) ?? false;
  Future<void> setEnabled(bool v) => prefs.setBool(_enabled, v);

  String get code => prefs.getString(_code) ?? '';
  Future<void> setCode(String v) => prefs.setString(_code, v);

  /// This device's name as shown to the other device.
  String get deviceName => prefs.getString(_name) ?? defaultDeviceName();

  static String defaultDeviceName() {
    if (Platform.isAndroid) return 'Android phone';
    final h = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '').replaceAll('-', ' ');
    return h.isEmpty ? 'Mac' : h;
  }

  Future<void> setDeviceName(String v) => prefs.setString(_name, v.trim());

  bool get autoSync => prefs.getBool(_auto) ?? true;

  /// Android: keep the app running (ongoing notification) so sync also works
  /// while the phone is locked.
  bool get whileLocked => prefs.getBool('sync_while_locked') ?? true;
  Future<void> setWhileLocked(bool v) => prefs.setBool('sync_while_locked', v);
  Future<void> setAutoSync(bool v) => prefs.setBool(_auto, v);

  /// Periodic sync interval while the app runs: 1, 5 or 15 minutes.
  int get intervalMin => prefs.getInt(_interval) ?? 5;
  Future<void> setIntervalMin(int v) => prefs.setInt(_interval, v);

  List<PairedPeer> get peers => [
    for (final j in jsonDecode(prefs.getString(_peers) ?? '[]') as List) PairedPeer.fromJson(j as Map<String, dynamic>),
  ];

  Future<void> setPeers(List<PairedPeer> peers) =>
      prefs.setString(_peers, jsonEncode([for (final p in peers) p.toJson()]));

  /// Records a successful session with the peer at [address]; returns the
  /// updated list (most recent first). Shared by foreground and background sync.
  Future<List<PairedPeer>> recordSession({
    required String peerId,
    required String peerName,
    required String host,
    required int port,
    required int sent,
    required int received,
  }) async {
    final peer = PairedPeer(
      id: peerId,
      name: peerName,
      host: host,
      port: port,
      lastSyncAt: DateTime.now(),
      lastSent: sent,
      lastReceived: received,
    );
    final list = [peer, ...peers.where((p) => p.id != peerId)];
    await setPeers(list);
    return list;
  }
}

/// "Sent 4, received 12", or "Up to date" when a sync had nothing to exchange.
String syncResultText(int sent, int received) =>
    sent == 0 && received == 0 ? 'Up to date' : 'Sent $sent, received $received';
