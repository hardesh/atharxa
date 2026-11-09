import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/workout_repo.dart';
import '../services/strava.dart';
import 'core_providers.dart';

/// HTTP client for Strava; tests override it.
final stravaHttpProvider = Provider<http.Client?>((ref) => null);

/// This device's Strava connection (Connected services, Workout, upload).
final stravaProvider = NotifierProvider<StravaController, StravaState>(StravaController.new);

@immutable
class StravaState {
  const StravaState({this.account, this.busy = false, this.error, this.message});
  final StravaAccount? account;
  final bool busy;
  final String? error;

  /// Result of the last import ("3 new activities").
  final String? message;

  bool get connected => account?.connected ?? false;
}

class StravaController extends Notifier<StravaState> {
  @override
  StravaState build() =>
      StravaState(account: StravaAccount.fromJson(ref.read(prefsProvider).getString(DeviceKeys.strava)));

  Future<void> _store(StravaAccount a) async {
    await ref.read(prefsProvider).setString(DeviceKeys.strava, a.toJson());
    if (ref.mounted) state = StravaState(account: a, busy: state.busy, message: state.message);
  }

  StravaClient _client() => StravaClient(state.account!, save: _store, client: ref.read(stravaHttpProvider));

  /// Saves the user's Strava API app credentials (keeps an existing sign-in
  /// only if they are unchanged).
  Future<void> setCredentials(String clientId, String clientSecret) async {
    final old = state.account;
    final same = old != null && old.clientId == clientId && old.clientSecret == clientSecret;
    await _store(
      same
          ? old
          : StravaAccount(
              clientId: clientId.trim(),
              clientSecret: clientSecret.trim(),
              uploadByDefault: old?.uploadByDefault ?? false,
            ),
    );
  }

  /// Finishes sign-in with the code Strava returned, then imports.
  Future<void> connect(String code) => _run(() async {
    await _client().connect(code);
    await _import();
  });

  Future<void> disconnect() => _run(() async {
    await _client().disconnect();
    await _store(state.account!.copyWith(disconnect: true));
  });

  Future<void> importNow() => _run(_import);

  /// Imports at most once an hour, when Workout opens.
  Future<void> importIfStale() async {
    final last = state.account?.lastImportAt;
    if (!state.connected || state.busy) return;
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return;
    await _run(_import, quiet: true);
  }

  Future<void> _import() async {
    final n = await _client().importActivities(ref.read(dbProvider));
    if (!ref.mounted) return;
    state = StravaState(account: state.account, busy: true, message: n == 0 ? 'Up to date' : '$n new or updated');
  }

  Future<void> setUploadByDefault(bool on) => _store(state.account!.copyWith(uploadByDefault: on));

  /// Uploads a finished session and remembers its Strava id. Returns an error
  /// message, or null.
  Future<String?> upload(WorkoutSession s) async {
    try {
      final id = await _client().uploadSession(s);
      await WorkoutRepo(ref.read(dbProvider)).setStravaId(s.id, id);
      return null;
    } on StravaException catch (e) {
      return e.message;
    } on Exception {
      return 'Couldn’t reach Strava. Check the connection.';
    }
  }

  Future<void> _run(Future<void> Function() f, {bool quiet = false}) async {
    state = StravaState(account: state.account, busy: true, message: state.message);
    try {
      await f();
      if (ref.mounted) state = StravaState(account: state.account, message: state.message);
    } on StravaException catch (e) {
      if (ref.mounted) state = StravaState(account: state.account, error: quiet ? null : e.message);
    } on Exception {
      if (ref.mounted) {
        state = StravaState(
          account: state.account,
          error: quiet ? null : 'Couldn’t reach Strava. Check the connection.',
        );
      }
    }
  }
}
