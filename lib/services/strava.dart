import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../data/db.dart';
import '../data/workout_repo.dart';

/// Strava connection for this device (DESIGN.md §7.5). The user registers
/// their own Strava API app (callback domain `localhost`) and enters its
/// Client ID and Secret; tokens stay on this device and never sync.
class StravaAccount {
  const StravaAccount({
    required this.clientId,
    required this.clientSecret,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.athlete,
    this.uploadByDefault = false,
    this.lastImportAt,
  });

  final String clientId, clientSecret;
  final String? accessToken, refreshToken;

  /// Seconds since epoch.
  final int? expiresAt;

  /// "Harshal D."
  final String? athlete;
  final bool uploadByDefault;
  final DateTime? lastImportAt;

  bool get connected => refreshToken != null;

  StravaAccount copyWith({
    String? accessToken,
    String? refreshToken,
    int? expiresAt,
    String? athlete,
    bool? uploadByDefault,
    DateTime? lastImportAt,
    bool disconnect = false,
  }) => StravaAccount(
    clientId: clientId,
    clientSecret: clientSecret,
    accessToken: disconnect ? null : accessToken ?? this.accessToken,
    refreshToken: disconnect ? null : refreshToken ?? this.refreshToken,
    expiresAt: disconnect ? null : expiresAt ?? this.expiresAt,
    athlete: disconnect ? null : athlete ?? this.athlete,
    uploadByDefault: uploadByDefault ?? this.uploadByDefault,
    lastImportAt: disconnect ? null : lastImportAt ?? this.lastImportAt,
  );

  String toJson() => jsonEncode({
    'client_id': clientId,
    'client_secret': clientSecret,
    'access_token': ?accessToken,
    'refresh_token': ?refreshToken,
    'expires_at': ?expiresAt,
    'athlete': ?athlete,
    'upload_by_default': uploadByDefault,
    if (lastImportAt != null) 'last_import_at': lastImportAt!.toIso8601String(),
  });

  static StravaAccount? fromJson(String? s) {
    if (s == null) return null;
    final j = jsonDecode(s) as Map<String, Object?>;
    return StravaAccount(
      clientId: j['client_id'] as String,
      clientSecret: j['client_secret'] as String,
      accessToken: j['access_token'] as String?,
      refreshToken: j['refresh_token'] as String?,
      expiresAt: j['expires_at'] as int?,
      athlete: j['athlete'] as String?,
      uploadByDefault: j['upload_by_default'] == true,
      lastImportAt: DateTime.tryParse(j['last_import_at'] as String? ?? ''),
    );
  }
}

/// A Strava request that failed, with a message for the user.
class StravaException implements Exception {
  const StravaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Strava API calls. [save] persists token refreshes.
class StravaClient {
  StravaClient(this.account, {required this.save, http.Client? client}) : _http = client ?? http.Client();

  StravaAccount account;
  final Future<void> Function(StravaAccount) save;
  final http.Client _http;

  /// Where Strava sends the browser after sign-in; the sign-in page catches
  /// it before it loads (nothing listens on localhost).
  static const redirectUri = 'http://localhost/strava-callback';

  /// Read activities (including private ones) and upload workouts.
  static const scopes = 'read,activity:read_all,activity:write';

  static Uri authorizeUrl(String clientId) => Uri.https('www.strava.com', '/oauth/authorize', {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'approval_prompt': 'auto',
    'scope': scopes,
  });

  /// Exchanges the sign-in [code] for tokens.
  Future<StravaAccount> connect(String code) async {
    final j = await _token({'grant_type': 'authorization_code', 'code': code});
    final a = j['athlete'] as Map<String, Object?>? ?? const {};
    final name = [a['firstname'], a['lastname']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    account = account.copyWith(
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      expiresAt: (j['expires_at'] as num).toInt(),
      athlete: name.isEmpty ? null : name,
    );
    await save(account);
    return account;
  }

  /// Revokes access on Strava's side (best effort).
  Future<void> disconnect() async {
    final t = account.accessToken;
    if (t != null) {
      await _http
          .post(Uri.https('www.strava.com', '/oauth/deauthorize'), body: {'access_token': t})
          .catchError((_) => http.Response('', 0));
    }
  }

  Future<Map<String, Object?>> _token(Map<String, String> grant) async {
    final res = await _http.post(
      Uri.https('www.strava.com', '/oauth/token'),
      body: {'client_id': account.clientId, 'client_secret': account.clientSecret, ...grant},
    );
    if (res.statusCode == 400 || res.statusCode == 401) {
      throw const StravaException(
        'Strava refused the Client ID or Secret, or the sign-in expired. Check them and connect again.',
      );
    }
    if (res.statusCode != 200) throw StravaException('Strava is not responding (${res.statusCode}).');
    return jsonDecode(res.body) as Map<String, Object?>;
  }

  /// A valid access token, refreshed when it expires within 5 minutes.
  Future<String> _access() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (account.accessToken != null && (account.expiresAt ?? 0) > now + 300) return account.accessToken!;
    final refresh = account.refreshToken;
    if (refresh == null) throw const StravaException('Connect Strava first.');
    final j = await _token({'grant_type': 'refresh_token', 'refresh_token': refresh});
    account = account.copyWith(
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      expiresAt: (j['expires_at'] as num).toInt(),
    );
    await save(account);
    return account.accessToken!;
  }

  Future<http.Response> _api(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? body,
  }) async {
    final uri = Uri.https('www.strava.com', '/api/v3$path', query);
    final headers = {'Authorization': 'Bearer ${await _access()}'};
    final res = method == 'POST'
        ? await _http.post(uri, headers: headers, body: body)
        : await _http.get(uri, headers: headers);
    if (res.statusCode == 401) throw const StravaException('Strava access was revoked. Connect again.');
    if (res.statusCode == 429) throw const StravaException('Strava’s rate limit was reached. Try again in 15 minutes.');
    if (res.statusCode >= 300) throw StravaException('Strava request failed (${res.statusCode}).');
    return res;
  }

  /// Imports activities since the last import (or the last 90 days) into
  /// `strava_activities`; returns how many were new or changed.
  Future<int> importActivities(AppDb db) async {
    final since =
        account.lastImportAt?.subtract(const Duration(days: 2)) ?? DateTime.now().subtract(const Duration(days: 90));
    final started = DateTime.now();
    var count = 0;
    for (var page = 1; page <= 10; page++) {
      final res = await _api(
        'GET',
        '/athlete/activities',
        query: {'after': '${since.millisecondsSinceEpoch ~/ 1000}', 'per_page': '100', 'page': '$page'},
      );
      final list = (jsonDecode(res.body) as List).whereType<Map<String, Object?>>().toList();
      for (final a in list) {
        if (await db.saveIfChanged('strava_activities', activityRow(a))) count++;
      }
      if (list.length < 100) break;
    }
    account = account.copyWith(lastImportAt: started);
    await save(account);
    return count;
  }

  /// A Strava SummaryActivity as a `strava_activities` row. The row id is
  /// derived from Strava's id, so both devices import the same row.
  static Map<String, Object?> activityRow(Map<String, Object?> a) => {
    'id': 'strava-${a['id']}',
    'type': (a['sport_type'] ?? a['type'] ?? 'Workout') as String,
    'name': a['name'] as String?,
    'start': DateTime.parse(a['start_date'] as String).millisecondsSinceEpoch,
    'distance_m': (a['distance'] as num?)?.toDouble(),
    'moving_time_s': (a['moving_time'] as num?)?.toInt(),
  };

  /// Uploads a finished gym session as a manual Weight Training activity
  /// (it gets the athlete's default visibility); returns Strava's id.
  Future<String> uploadSession(WorkoutSession s) async {
    final end = s.endedAt ?? DateTime.now();
    final res = await _api(
      'POST',
      '/activities',
      body: {
        'name': s.planName,
        'sport_type': 'WeightTraining',
        'start_date_local': s.startedAt.toIso8601String(),
        'elapsed_time': '${end.difference(s.startedAt).inSeconds}',
        'description': [
          '${s.sets.length} sets · ${s.volume.round()} kg volume',
          if ((s.row['notes'] as String?)?.isNotEmpty == true) s.row['notes'] as String,
          'Logged with ${AppInfo.name}',
        ].join('\n'),
      },
    );
    return '${(jsonDecode(res.body) as Map)['id']}';
  }
}
