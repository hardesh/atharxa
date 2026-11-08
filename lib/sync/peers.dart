import 'dart:convert';

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

  PairedPeer copyWith({
    String? name,
    String? host,
    int? port,
    DateTime? lastSyncAt,
    int? lastSent,
    int? lastReceived,
  }) => PairedPeer(
    id: id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastSent: lastSent ?? this.lastSent,
    lastReceived: lastReceived ?? this.lastReceived,
  );

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

  String? get deviceName => prefs.getString(_name);
  Future<void> setDeviceName(String v) => prefs.setString(_name, v.trim());

  bool get autoSync => prefs.getBool(_auto) ?? true;
  Future<void> setAutoSync(bool v) => prefs.setBool(_auto, v);

  /// Periodic sync interval while the app runs: 1, 5 or 15 minutes.
  int get intervalMin => prefs.getInt(_interval) ?? 5;
  Future<void> setIntervalMin(int v) => prefs.setInt(_interval, v);

  List<PairedPeer> get peers => [
    for (final j in jsonDecode(prefs.getString(_peers) ?? '[]') as List) PairedPeer.fromJson(j as Map<String, dynamic>),
  ];

  Future<void> setPeers(List<PairedPeer> peers) =>
      prefs.setString(_peers, jsonEncode([for (final p in peers) p.toJson()]));
}
