import 'dart:convert';

import 'package:atharxa/data/workout_repo.dart';
import 'package:atharxa/services/strava.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void main() {
  const creds = StravaAccount(clientId: '123', clientSecret: 's3cret');
  final future = DateTime.now().add(const Duration(hours: 5)).millisecondsSinceEpoch ~/ 1000;

  Map<String, Object?> activity(int id, String type, String start, double m) => {
    'id': id,
    'name': '$type $id',
    'sport_type': type,
    'start_date': start,
    'distance': m,
    'moving_time': 1800,
  };

  test('sign-in URL asks for read and upload access and comes back to localhost', () {
    final u = StravaClient.authorizeUrl('123');
    expect(u.host, 'www.strava.com');
    expect(u.queryParameters['client_id'], '123');
    expect(u.queryParameters['scope'], 'read,activity:read_all,activity:write');
    expect(u.queryParameters['redirect_uri'], 'http://localhost/strava-callback');
  });

  test('account JSON round-trips; disconnect keeps the app credentials', () {
    final a = creds.copyWith(accessToken: 'a', refreshToken: 'r', expiresAt: 1, athlete: 'H D', uploadByDefault: true);
    final back = StravaAccount.fromJson(a.toJson())!;
    expect([back.clientId, back.refreshToken, back.athlete, back.uploadByDefault], ['123', 'r', 'H D', true]);
    final off = back.copyWith(disconnect: true);
    expect([off.connected, off.clientSecret, off.uploadByDefault], [false, 's3cret', true]);
  });

  test('connect exchanges the code and remembers the athlete', () async {
    StravaAccount? saved;
    final client = StravaClient(
      creds,
      save: (a) async => saved = a,
      client: MockClient((r) async {
        expect(r.url.path, '/oauth/token');
        expect(r.bodyFields, containsPair('code', 'abc'));
        expect(r.bodyFields, containsPair('client_secret', 's3cret'));
        return http.Response(
          jsonEncode({
            'access_token': 'A',
            'refresh_token': 'R',
            'expires_at': future,
            'athlete': {'firstname': 'Harshal', 'lastname': 'D'},
          }),
          200,
        );
      }),
    );
    await client.connect('abc');
    expect(saved!.connected, isTrue);
    expect(saved!.athlete, 'Harshal D');
  });

  test('an expired token is refreshed before calling the API', () async {
    final calls = <String>[];
    final client = StravaClient(
      creds.copyWith(accessToken: 'old', refreshToken: 'R', expiresAt: 0),
      save: (_) async {},
      client: MockClient((r) async {
        calls.add(r.url.path);
        if (r.url.path == '/oauth/token') {
          expect(r.bodyFields['grant_type'], 'refresh_token');
          return http.Response(jsonEncode({'access_token': 'new', 'refresh_token': 'R2', 'expires_at': future}), 200);
        }
        expect(r.headers['Authorization'], 'Bearer new');
        return http.Response('[]', 200);
      }),
    );
    await client.importActivities(await openTestDb());
    expect(calls, ['/oauth/token', '/api/v3/athlete/activities']);
    expect(client.account.refreshToken, 'R2');
  });

  test('import saves activities once; re-importing unchanged ones writes nothing', () async {
    final db = await openTestDb();
    final list = [activity(1, 'Run', '2026-11-09T06:00:00Z', 5230), activity(2, 'Ride', '2026-11-08T07:00:00Z', 20100)];
    final client = StravaClient(
      creds.copyWith(accessToken: 'A', refreshToken: 'R', expiresAt: future),
      save: (_) async {},
      client: MockClient((_) async => http.Response(jsonEncode(list), 200)),
    );
    expect(await client.importActivities(db), 2);
    expect(await client.importActivities(db), 0);
    final week = await WorkoutRepo(db).stravaBetween('2026-11-03', '2026-11-09');
    expect(week.map((a) => (a.name, a.isRun, a.isRide, a.km)), [
      ('Run 1', true, false, 5.23),
      ('Ride 2', false, true, 20.1),
    ]);
  });

  test('upload creates a Weight Training activity', () async {
    late Map<String, String> sent;
    final client = StravaClient(
      creds.copyWith(accessToken: 'A', refreshToken: 'R', expiresAt: future),
      save: (_) async {},
      client: MockClient((r) async {
        sent = r.bodyFields;
        return http.Response(jsonEncode({'id': 987}), 201);
      }),
    );
    final start = DateTime(2026, 11, 9, 7);
    final session = WorkoutSession({
      'id': 's',
      'plan_name': 'Lower body A',
      'day': '2026-11-09',
      'started_at': start.millisecondsSinceEpoch,
      'ended_at': start.add(const Duration(minutes: 52)).millisecondsSinceEpoch,
      'notes': 'Felt strong',
    }, const []);
    expect(await client.uploadSession(session), '987');
    expect(sent['sport_type'], 'WeightTraining');
    expect(sent['name'], 'Lower body A');
    expect(sent['elapsed_time'], '3120');
    expect(sent['description'], contains('Felt strong'));
  });

  test('a revoked token gives a clear message', () async {
    final client = StravaClient(
      creds.copyWith(accessToken: 'A', refreshToken: 'R', expiresAt: future),
      save: (_) async {},
      client: MockClient((_) async => http.Response('', 401)),
    );
    await expectLater(
      client.importActivities(await openTestDb()),
      throwsA(isA<StravaException>().having((e) => e.message, 'message', contains('Connect again'))),
    );
  });
}
