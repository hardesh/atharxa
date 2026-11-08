import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../data/db.dart';

class Peer {
  Peer({required this.id, required this.name, required this.host, required this.port});
  final String id, name, host;
  final int port;
  String get address => '$host:$port';
}

/// Peer-to-peer sync over the local network. No cloud involved.
///
/// * Each device runs a tiny HTTP server (port [port]) and advertises it via
///   mDNS/Bonjour as `_superapp._tcp`.
/// * Both devices must share the same pairing code; every request carries it.
/// * A sync session: the client sends its rows changed since it last pushed to
///   that peer, the server merges them and replies with its own rows changed
///   since the client last pulled. Each side remembers cursors per peer.
class SyncService extends ChangeNotifier {
  SyncService(this.db, this.prefs);

  static const port = 47823;
  static const serviceType = '_superapp._tcp';

  final AppDb db;
  final SharedPreferences prefs;

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  Timer? _timer;

  final Map<String, Peer> peers = {};
  String status = 'Off';
  DateTime? lastSync;
  bool busy = false;

  bool get enabled => prefs.getBool('sync_enabled') ?? false;
  String get pairingCode => prefs.getString('sync_code') ?? '';
  List<String> get manualHosts => prefs.getStringList('sync_manual_hosts') ?? [];
  String get deviceName => prefs.getString('device_name') ?? Platform.localHostname;
  bool get running => _server != null;

  Future<void> configure({bool? enabled, String? code, List<String>? manualHosts, String? name}) async {
    if (enabled != null) await prefs.setBool('sync_enabled', enabled);
    if (code != null) await prefs.setString('sync_code', code.trim());
    if (manualHosts != null) await prefs.setStringList('sync_manual_hosts', manualHosts);
    if (name != null) await prefs.setString('device_name', name.trim());
    await stop();
    if (this.enabled && pairingCode.isNotEmpty) await start();
    notifyListeners();
  }

  Future<void> start() async {
    if (running || pairingCode.isEmpty) return;
    try {
      _server = await shelf_io.serve(_handler, InternetAddress.anyIPv4, port);
      status = 'Listening on port $port';
    } catch (e) {
      status = 'Could not start server: $e';
      notifyListeners();
      return;
    }
    await _startMdns();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncAll());
    notifyListeners();
    unawaited(Future.delayed(const Duration(seconds: 3), syncAll));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _server?.close(force: true);
    _server = null;
    try {
      await _broadcast?.stop();
      await _discovery?.stop();
    } catch (_) {}
    _broadcast = null;
    _discovery = null;
    peers.clear();
    status = 'Off';
    notifyListeners();
  }

  Future<void> _startMdns() async {
    try {
      final service = BonsoirService(name: deviceName, type: serviceType, port: port, attributes: {'id': db.deviceId});
      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.initialize();
      await _broadcast!.start();

      _discovery = BonsoirDiscovery(type: serviceType);
      await _discovery!.initialize();
      _discovery!.eventStream!.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            if (event.service.attributes['id'] != db.deviceId) {
              _discovery!.serviceResolver.resolveService(event.service);
            }
          case BonsoirDiscoveryServiceResolvedEvent():
            final s = event.service;
            final id = s.attributes['id'];
            final host = s.hostAddresses.where((a) => !a.contains(':')).firstOrNull ?? s.hostAddress;
            if (id != null && id != db.deviceId && host != null) {
              peers[id] = Peer(id: id, name: s.name, host: host, port: s.port);
              notifyListeners();
              unawaited(syncWith('$host:${s.port}'));
            }
          case BonsoirDiscoveryServiceLostEvent():
            peers.remove(event.service.attributes['id']);
            notifyListeners();
          default:
        }
      });
      await _discovery!.start();
    } catch (e) {
      // mDNS is a convenience; manual IP entry still works.
      status = '$status (auto-discovery unavailable: $e)';
    }
  }

  // ------------------------------------------------------------------ server

  Future<Response> _handler(Request req) async {
    if (req.headers['x-sync-code'] != pairingCode || pairingCode.isEmpty) {
      return Response.forbidden('bad pairing code');
    }
    final path = req.url.path;
    if (req.method == 'GET' && path == 'hello') {
      return _json({'deviceId': db.deviceId, 'name': deviceName});
    }
    if (req.method == 'POST' && path == 'sync') {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final peerId = body['deviceId'] as String;
      final since = (body['since'] as num).toInt();
      // Snapshot our rev *before* merging so the client's own rows that we
      // just stored aren't counted as "new" for it again.
      final maxRev = await db.currentRev();
      final outgoing = await db.changesSince(since);
      await db.merge((body['changes'] as Map).cast<String, dynamic>());
      lastSync = DateTime.now();
      status = 'Synced with ${body['name'] ?? peerId}';
      notifyListeners();
      return _json({'deviceId': db.deviceId, 'name': deviceName, 'changes': outgoing, 'rev': maxRev});
    }
    return Response.notFound('not found');
  }

  Response _json(Object o) => Response.ok(jsonEncode(o), headers: {'content-type': 'application/json'});

  // ------------------------------------------------------------------ client

  /// Sync with every discovered peer plus manually entered hosts.
  Future<void> syncAll() async {
    final targets = {...peers.values.map((p) => p.address), ...manualHosts.map(_withPort)};
    for (final t in targets) {
      await syncWith(t);
    }
  }

  String _withPort(String h) => h.contains(':') ? h : '$h:$port';

  Future<void> syncWith(String address) async {
    if (busy || pairingCode.isEmpty) return;
    busy = true;
    notifyListeners();
    try {
      final hello = await http
          .get(Uri.parse('http://$address/hello'), headers: {'x-sync-code': pairingCode})
          .timeout(const Duration(seconds: 5));
      if (hello.statusCode == 403) throw Exception('pairing code does not match');
      if (hello.statusCode != 200) throw Exception('HTTP ${hello.statusCode}');
      final peerId = (jsonDecode(hello.body) as Map)['deviceId'] as String;
      if (peerId == db.deviceId) return;

      final pushedKey = 'push_$peerId', pulledKey = 'pull_$peerId';
      final pushedRev = int.tryParse(await db.getMeta(pushedKey) ?? '') ?? 0;
      final pulledRev = int.tryParse(await db.getMeta(pulledKey) ?? '') ?? 0;
      final myRev = await db.currentRev();
      final mine = await db.changesSince(pushedRev);

      final res = await http
          .post(
            Uri.parse('http://$address/sync'),
            headers: {'x-sync-code': pairingCode, 'content-type': 'application/json'},
            body: jsonEncode({'deviceId': db.deviceId, 'name': deviceName, 'since': pulledRev, 'changes': mine}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final applied = await db.merge((body['changes'] as Map).cast<String, dynamic>());
      // Rows we just merged got new local revs; skip echoing them back.
      await db.setMeta(pushedKey, '${await db.currentRev()}');
      await db.setMeta(pulledKey, '${body['rev']}');
      lastSync = DateTime.now();
      final sent = mine.values.fold<int>(0, (a, l) => a + l.length);
      status = 'Synced with ${body['name']}: sent $sent, received $applied';
      // If local edits happened between snapshot and merge, they'd be skipped
      // by the cursor above, so fall back to the pre-sync rev in that case.
      if (await db.currentRev() != myRev + applied) {
        await db.setMeta(pushedKey, '$myRev');
      }
    } catch (e) {
      status = 'Sync with $address failed: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// IPv4 addresses of this device, shown in settings for manual pairing.
  static Future<List<String>> localAddresses() async {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in ifs)
        for (final a in i.addresses)
          if (!a.isLoopback) a.address,
    ];
  }
}
