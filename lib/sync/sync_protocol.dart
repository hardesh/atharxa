import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import '../data/db.dart';
import 'sync_auth.dart';

/// Default TCP port for sync (DESIGN.md §7.2).
const syncPort = 47811;
const _pageSize = 400;

enum SyncErrorKind { codeMismatch, unreachable, interrupted, syncOff, other }

class SyncException implements Exception {
  SyncException(this.kind, this.message, {this.received = 0, this.total = 0});
  final SyncErrorKind kind;
  final String message;
  final int received, total;

  @override
  String toString() => message;
}

class SyncOutcome {
  SyncOutcome({required this.peerId, required this.peerName, required this.sent, required this.received});
  final String peerId, peerName;
  final int sent, received;
}

typedef SyncProgress = void Function(int received, int total);

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
  SyncServer({required this.db, required this.auth, required this.name});

  final AppDb db;
  final SyncAuth auth;
  final String Function() name;

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
        return _reply(path, 200, {'id': db.deviceId, 'name': name()});
      case ('POST', '/v1/pull'):
        final since = (input['since'] as num?)?.toInt() ?? 0;
        final page = await db.changesPage(since, limit: _pageSize, excludeDevice: sender);
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
        return _reply(path, 200, {'applied': await db.merge(rows)});
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
  SyncClient({required this.db, required this.auth, required this.name, http.Client? client})
    : _http = client ?? http.Client();

  final AppDb db;
  final SyncAuth auth;
  final String name;
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
        await db.merge(rows);
        received += rows.length;
        since = (j['next'] as num).toInt();
        await db.setMeta(pullKey(peer.id), '$since');
        onProgress?.call(received, total);
        if (j['more'] != true) break;
      }
    } on SyncException catch (e) {
      if (e.kind == SyncErrorKind.unreachable) {
        // Lost the connection mid-session; cursors already saved → resumes.
        throw SyncException(
          SyncErrorKind.interrupted,
          'Sync interrupted — $received of $total received, will resume',
          received: received,
          total: total,
        );
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
    } on SocketException {
      throw SyncException(SyncErrorKind.unreachable, 'Device not reachable ($address)');
    } on TimeoutException {
      throw SyncException(SyncErrorKind.unreachable, 'Device not reachable ($address)');
    } on http.ClientException {
      throw SyncException(SyncErrorKind.unreachable, 'Device not reachable ($address)');
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
    if (res.statusCode == 503) throw SyncException(SyncErrorKind.syncOff, 'Sync is off on the other device');
    if (res.statusCode != 200) throw SyncException(SyncErrorKind.other, 'Sync failed (HTTP ${res.statusCode})');
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  void close() => _http.close();
}
