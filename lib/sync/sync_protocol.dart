import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import '../data/db.dart';
import 'sync_auth.dart';

/// Default TCP port for sync (DESIGN.md §7.2).
const syncPort = 47811;
const _pageSize = 400;

enum SyncErrorKind { codeMismatch, unreachable, interrupted, other }

class SyncException implements Exception {
  SyncException(this.kind, this.message, {this.peer});
  final SyncErrorKind kind;
  final String message;

  /// Name of the device the session was with, when known (for dialogs).
  final String? peer;

  SyncException withPeer(String name) => SyncException(kind, message, peer: name);

  @override
  String toString() => message;
}

/// A session another device ran against this one (server side).
class ServedSession {
  ServedSession({
    required this.peerId,
    required this.peerName,
    required this.host,
    required this.sent,
    required this.received,
  });
  final String peerId, peerName;
  final String? host;
  final int sent, received;
}

class SyncOutcome {
  SyncOutcome({required this.peerId, required this.peerName, required this.sent, required this.received});
  final String peerId, peerName;
  final int sent, received;
}

typedef SyncProgress = void Function(int received, int total);

/// "192.168.1.42" or "192.168.1.42:47811" → host + port (default [syncPort]).
({String host, int port}) parseAddress(String input) {
  final a = input.trim();
  final i = a.lastIndexOf(':');
  if (i < 0) return (host: a, port: syncPort);
  return (host: a.substring(0, i), port: int.tryParse(a.substring(i + 1)) ?? syncPort);
}

// ------------------------------------------------------------------ server

/// HTTP handler answering another device's sync session.
///
/// * `GET  /v1/hello` → `{id, name}`
/// * `POST /v1/pull {since}` → `{rows, next, more, remaining}` (rows the caller lacks)
/// * `POST /v1/push {rows}` → `{applied}`
///
/// Every request must be signed with the shared pairing code; responses are
/// signed too so the caller can tell a wrong code from a network problem.
class SyncServer {
  SyncServer({required this.db, required this.auth, required this.name, this.onSession});

  final AppDb db;
  final SyncAuth auth;
  final String Function() name;

  /// Called after each request of a session another device runs against us,
  /// with that session's running totals (so both sides show "Sent N,
  /// received M", not just the device that started it).
  final void Function(ServedSession)? onSession;

  /// Running totals per peer for the session in progress (reset on hello).
  final _sessions = <String, ({int sent, int received})>{};

  void _record(Request req, String peerId, {int sent = 0, int received = 0}) {
    final cur = _sessions[peerId] ?? (sent: 0, received: 0);
    final next = (sent: cur.sent + sent, received: cur.received + received);
    _sessions[peerId] = next;
    final info = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    onSession?.call(
      ServedSession(
        peerId: peerId,
        peerName: Uri.decodeComponent(req.headers[SyncHeaders.name] ?? ''),
        host: info?.remoteAddress.address,
        sent: next.sent,
        received: next.received,
      ),
    );
  }

  Future<Response> handle(Request req) async {
    final path = '/${req.url.path}';
    final body = await req.read().expand((c) => c).toList();
    final sender = req.headers[SyncHeaders.device] ?? '';
    final ts = int.tryParse(req.headers[SyncHeaders.ts] ?? '') ?? 0;
    final ok = auth.verify(
      method: req.method,
      path: path,
      ts: ts,
      sender: sender,
      body: body,
      signature: req.headers[SyncHeaders.sig],
    );
    if (!ok) return _reply(path, 401, {'error': 'bad_signature'});

    final input = body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    switch ((req.method, path)) {
      case ('GET', '/v1/hello'):
        _sessions.remove(sender);
        return _reply(path, 200, {'id': db.deviceId, 'name': name()});
      case ('POST', '/v1/pull'):
        final since = (input['since'] as num?)?.toInt() ?? 0;
        final page = await db.changesPage(since, limit: _pageSize, excludeDevice: sender);
        _record(req, sender, sent: page.rows.length);
        final remaining = input['count'] == true ? await db.countChanges(since, excludeDevice: sender) : null;
        return _reply(path, 200, {
          'rows': [for (final r in page.rows) r.toJson()],
          'next': page.next,
          'more': page.more,
          'remaining': ?remaining,
        });
      case ('POST', '/v1/push'):
        final rows = [
          for (final j in (input['rows'] as List? ?? const [])) SyncRow.fromJson(j as Map<String, dynamic>),
        ];
        final applied = await db.merge(rows);
        if (applied > 0) debugPrint('[sync] received $applied rows pushed by $sender');
        _record(req, sender, received: rows.length);
        return _reply(path, 200, {'applied': applied});
      default:
        return _reply(path, 404, {'error': 'not_found'});
    }
  }

  Response _reply(String path, int status, Map<String, Object?> json) {
    final bytes = utf8.encode(jsonEncode(json));
    final ts = DateTime.now().millisecondsSinceEpoch;
    return Response(
      status,
      body: bytes,
      headers: {
        'content-type': 'application/json',
        SyncHeaders.device: db.deviceId,
        SyncHeaders.ts: '$ts',
        SyncHeaders.sig: auth.sign(method: 'RESP', path: path, ts: ts, sender: db.deviceId, body: bytes),
      },
    );
  }
}

// ------------------------------------------------------------------ client

/// Runs one sync session against a peer at `host:port`.
class SyncClient {
  SyncClient({required this.db, required this.auth, this.deviceName = '', http.Client? client})
    : _http = client ?? http.Client();

  final AppDb db;
  final SyncAuth auth;

  /// Sent to the peer so its paired list can show this device's name.
  final String deviceName;
  final http.Client _http;

  static String pushKey(String peerId) => 'push_$peerId';
  static String pullKey(String peerId) => 'pull_$peerId';

  /// Forget cursors so the next session exchanges every row ("Full resync").
  Future<void> resetCursors(String peerId) async {
    await db.setMeta(pushKey(peerId), '0');
    await db.setMeta(pullKey(peerId), '0');
  }

  /// Hello only: returns `(id, name)` or throws [SyncException].
  Future<({String id, String name})> hello(String address) async {
    final j = await _call(address, 'GET', '/v1/hello', null, connecting: true);
    return (id: j['id'] as String, name: j['name'] as String);
  }

  Future<SyncOutcome> syncWith(String address, {bool full = false, SyncProgress? onProgress}) async {
    final peer = await hello(address);
    if (peer.id == db.deviceId) throw SyncException(SyncErrorKind.other, 'That address is this device');
    if (full) await resetCursors(peer.id);

    var sent = 0, received = 0, total = 0;
    try {
      // Push: our rows the peer hasn't seen, page by page.
      var since = int.tryParse(await db.getMeta(pushKey(peer.id)) ?? '') ?? 0;
      while (true) {
        final page = await db.changesPage(since, limit: _pageSize, excludeDevice: peer.id);
        if (page.rows.isNotEmpty) {
          await _call(address, 'POST', '/v1/push', {
            'rows': [for (final r in page.rows) r.toJson()],
          });
          sent += page.rows.length;
        }
        since = page.next;
        await db.setMeta(pushKey(peer.id), '$since');
        if (!page.more) break;
      }

      // Pull: the peer's rows we haven't seen, with progress.
      since = int.tryParse(await db.getMeta(pullKey(peer.id)) ?? '') ?? 0;
      var first = true;
      while (true) {
        final j = await _call(address, 'POST', '/v1/pull', {'since': since, 'count': first});
        if (first) total = (j['remaining'] as num?)?.toInt() ?? 0;
        first = false;
        final rows = [for (final r in j['rows'] as List) SyncRow.fromJson(r as Map<String, dynamic>)];
        since = (j['next'] as num).toInt();
        await db.merge(rows, cursor: (pullKey(peer.id), '$since'));
        received += rows.length;
        onProgress?.call(received, total);
        if (j['more'] != true) break;
      }
    } on SyncException catch (e) {
      if (e.kind == SyncErrorKind.unreachable) {
        // Lost the connection mid-session; cursors already saved → resumes.
        throw SyncException(SyncErrorKind.interrupted, 'Sync interrupted — $received of $total received, will resume');
      }
      rethrow;
    }
    return SyncOutcome(peerId: peer.id, peerName: peer.name, sent: sent, received: received);
  }

  Future<Map<String, dynamic>> _call(
    String address,
    String method,
    String path,
    Map<String, Object?>? json, {
    bool connecting = false,
  }) async {
    final body = json == null ? <int>[] : utf8.encode(jsonEncode(json));
    final ts = DateTime.now().millisecondsSinceEpoch;
    final headers = {
      'content-type': 'application/json',
      SyncHeaders.device: db.deviceId,
      SyncHeaders.name: Uri.encodeComponent(deviceName),
      SyncHeaders.ts: '$ts',
      SyncHeaders.sig: auth.sign(method: method, path: path, ts: ts, sender: db.deviceId, body: body),
    };
    final uri = Uri.parse('http://$address$path');
    final http.Response res;
    try {
      final req = http.Request(method, uri)
        ..headers.addAll(headers)
        ..bodyBytes = body;
      res = await http.Response.fromStream(
        await _http.send(req).timeout(Duration(seconds: connecting ? 5 : 30)),
      ).timeout(const Duration(seconds: 60));
    } on Exception catch (e) {
      if (e is SocketException || e is TimeoutException || e is http.ClientException) {
        throw SyncException(SyncErrorKind.unreachable, 'Device not reachable ($address)');
      }
      rethrow;
    }

    final verified = auth.verify(
      method: 'RESP',
      path: path,
      ts: int.tryParse(res.headers[SyncHeaders.ts] ?? '') ?? 0,
      sender: res.headers[SyncHeaders.device] ?? '',
      body: res.bodyBytes,
      signature: res.headers[SyncHeaders.sig],
    );
    if (res.statusCode == 401 || !verified) {
      throw SyncException(SyncErrorKind.codeMismatch, 'Pairing code does not match');
    }
    if (res.statusCode != 200) throw SyncException(SyncErrorKind.other, 'Sync failed (HTTP ${res.statusCode})');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  void close() => _http.close();
}
