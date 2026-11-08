import 'dart:io';

import 'package:atharxa/data/db.dart';
import 'package:atharxa/sync/sync_auth.dart';
import 'package:atharxa/sync/sync_protocol.dart';
import 'package:convert/convert.dart' show hex;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'helpers.dart';

/// Starts [db]'s sync server on a free local port; returns its address.
Future<(HttpServer, String)> serve(
  AppDb db,
  String code, {
  String name = 'Mac',
  void Function(ServedSession)? onSession,
}) async {
  final server = SyncServer(db: db, auth: SyncAuth(code), name: () => name, onSession: onSession);
  final http = await shelf_io.serve(server.handle, InternetAddress.loopbackIPv4, 0);
  return (http, '127.0.0.1:${http.port}');
}

Future<int> waterCount(AppDb db) async => (await db.query('water_logs')).length;

void main() {
  test('PBKDF2-HMAC-SHA256 matches RFC 7914 test vectors', () {
    expect(
      hex.encode(SyncAuth.pbkdf2('password'.codeUnits, 'salt'.codeUnits, 1, 32)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      hex.encode(SyncAuth.pbkdf2('password'.codeUnits, 'salt'.codeUnits, 2, 32)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test('signatures reject other codes and stale timestamps', () {
    final a = SyncAuth('482913'), b = SyncAuth('111111');
    final now = DateTime.now().millisecondsSinceEpoch;
    final sig = a.sign(method: 'GET', path: '/v1/hello', ts: now, sender: 'x', body: const []);
    expect(a.verify(method: 'GET', path: '/v1/hello', ts: now, sender: 'x', body: const [], signature: sig), isTrue);
    expect(b.verify(method: 'GET', path: '/v1/hello', ts: now, sender: 'x', body: const [], signature: sig), isFalse);
    final old = now - const Duration(minutes: 10).inMilliseconds;
    final oldSig = a.sign(method: 'GET', path: '/v1/hello', ts: old, sender: 'x', body: const []);
    expect(
      a.verify(method: 'GET', path: '/v1/hello', ts: old, sender: 'x', body: const [], signature: oldSig),
      isFalse,
    );
  });

  test('phone and Mac converge both ways; second sync sends nothing new', () async {
    final phone = await openTestDb(), mac = await openTestDb();
    final (server, address) = await serve(mac, '482913');
    addTearDown(() => server.close(force: true));

    await phone.save('water_logs', {'day': '2026-11-08', 'ml': 250, 'logged_at': 1, 'source': 'today'});
    await mac.save('water_logs', {'day': '2026-11-08', 'ml': 500, 'logged_at': 2, 'source': 'mac'});
    await mac.setPref('goal_kcal', '2000');

    final client = SyncClient(db: phone, auth: SyncAuth('482913'));
    final first = await client.syncWith(address);
    expect(first.peerName, 'Mac');
    expect(first.sent, greaterThan(0));
    expect(first.received, greaterThan(0));
    expect(await waterCount(phone), 2);
    expect(await waterCount(mac), 2);
    expect(await phone.getPref('goal_kcal'), '2000');

    // Nothing changed: no echo of the rows we just exchanged.
    final second = await client.syncWith(address);
    expect(second.sent, 0);
    expect(second.received, 0);

    // A delete on the phone reaches the Mac.
    final id = (await phone.query('water_logs', where: 'ml = 250')).single['id'] as String;
    await phone.delete('water_logs', id);
    await client.syncWith(address);
    expect(await waterCount(mac), 1);
    client.close();
  });

  test('wrong pairing code is reported as a code mismatch', () async {
    final phone = await openTestDb(), mac = await openTestDb();
    final (server, address) = await serve(mac, '482913');
    addTearDown(() => server.close(force: true));
    final client = SyncClient(db: phone, auth: SyncAuth('000000'));
    await expectLater(
      client.syncWith(address),
      throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncErrorKind.codeMismatch)),
    );
    client.close();
  });

  test('unreachable device is reported as such', () async {
    final phone = await openTestDb();
    final client = SyncClient(db: phone, auth: SyncAuth('482913'));
    await expectLater(
      client.syncWith('127.0.0.1:1'),
      throwsA(isA<SyncException>().having((e) => e.kind, 'kind', SyncErrorKind.unreachable)),
    );
    client.close();
  });

  test('large changes are paged and fully transferred', () async {
    final phone = await openTestDb(), mac = await openTestDb();
    final (server, address) = await serve(mac, '482913');
    addTearDown(() => server.close(force: true));
    for (var i = 0; i < 950; i++) {
      await mac.save('water_logs', {'day': '2026-11-08', 'ml': i + 1, 'logged_at': i, 'source': 'mac'});
    }
    final progress = <int>[];
    final client = SyncClient(db: phone, auth: SyncAuth('482913'));
    final r = await client.syncWith(address, onProgress: (rec, total) => progress.add(rec));
    expect(await waterCount(phone), 950);
    expect(progress.length, greaterThan(1)); // more than one page
    expect(r.received, greaterThanOrEqualTo(950));
    client.close();
  });

  test('the answering device records the session too (sent/received, name)', () async {
    final phone = await openTestDb(), mac = await openTestDb();
    ServedSession? last;
    final (server, address) = await serve(mac, '482913', onSession: (s) => last = s);
    addTearDown(() => server.close(force: true));
    await phone.save('water_logs', {'day': '2026-11-08', 'ml': 250, 'logged_at': 1, 'source': 'today'});
    await mac.save('water_logs', {'day': '2026-11-08', 'ml': 500, 'logged_at': 2, 'source': 'mac'});

    final client = SyncClient(db: phone, auth: SyncAuth('482913'), deviceName: 'Android phone');
    final r = await client.syncWith(address);
    client.close();

    expect(last, isNotNull);
    expect(last!.peerId, phone.deviceId);
    expect(last!.peerName, 'Android phone');
    expect(last!.host, '127.0.0.1');
    expect(last!.received, r.sent); // what the phone sent, the Mac received
    expect(last!.sent, r.received);
  });
}
