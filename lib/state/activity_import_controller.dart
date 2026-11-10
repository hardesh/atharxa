import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_clock.dart';
import '../services/health_import.dart';
import 'core_providers.dart';

/// The Health Connect reader; tests override it.
final healthImportProvider = Provider<HealthImport>((ref) => HealthImport());

/// Importing workouts from Health Connect on this phone (Connected
/// services, Workout). On the Mac the imported rows simply arrive by sync.
final activityImportProvider = NotifierProvider<ActivityImportController, ActivityImportState>(
  ActivityImportController.new,
);

/// Where reading workouts from Health Connect stands on this device.
enum HealthStatus {
  /// Not Android: activities arrive from the phone by sync.
  unsupported,
  checking,
  unavailable,
  needsPermission,
  connected,
}

@immutable
class ActivityImportState {
  const ActivityImportState({
    this.status = HealthStatus.checking,
    this.busy = false,
    this.lastImport,
    this.message,
    this.error,
  });

  final HealthStatus status;
  final bool busy;
  final DateTime? lastImport;

  /// The result of the last import ("3 new"), or why it failed. Each update
  /// replaces both, so an old message never sits next to a new error.
  final String? message, error;

  bool get supported => status != HealthStatus.unsupported;
  bool get granted => status == HealthStatus.connected;

  ActivityImportState copyWith({
    HealthStatus? status,
    bool? busy,
    DateTime? lastImport,
    String? message,
    String? error,
  }) => ActivityImportState(
    status: status ?? this.status,
    busy: busy ?? this.busy,
    lastImport: lastImport ?? this.lastImport,
    message: message,
    error: error,
  );
}

class ActivityImportController extends Notifier<ActivityImportState> {
  HealthImport get _hc => ref.read(healthImportProvider);

  @override
  ActivityImportState build() => ActivityImportState(
    status: Platform.isAndroid ? HealthStatus.checking : HealthStatus.unsupported,
    lastImport: DateTime.tryParse(ref.read(prefsProvider).getString(DeviceKeys.activitiesImportedAt) ?? ''),
  );

  /// Reads whether Health Connect is there and allowed (cheap). Updates the
  /// state only when that changed.
  Future<void> check() async {
    if (!state.supported) return;
    HealthStatus status;
    String? error;
    try {
      status = !await _hc.available()
          ? HealthStatus.unavailable
          : await _hc.granted()
          ? HealthStatus.connected
          : HealthStatus.needsPermission;
    } on Exception catch (e) {
      status = HealthStatus.unavailable;
      error = 'Health Connect: $e';
    }
    if (ref.mounted && (status != state.status || error != state.error)) {
      state = state.copyWith(status: status, message: state.message, error: error);
    }
  }

  /// Asks for access, then imports.
  Future<void> connect() async {
    final ok = await _hc.requestAccess();
    if (!ref.mounted) return;
    state = state.copyWith(status: ok ? HealthStatus.connected : HealthStatus.needsPermission);
    if (ok) await importNow();
  }

  Future<void> importNow() async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    try {
      final started = AppClock.now();
      final since = state.lastImport?.subtract(const Duration(days: 2)) ?? started.subtract(const Duration(days: 90));
      final n = await _hc.importSince(ref.read(dbProvider), since);
      await ref.read(prefsProvider).setString(DeviceKeys.activitiesImportedAt, started.toIso8601String());
      if (ref.mounted) {
        state = state.copyWith(busy: false, lastImport: started, message: n == 0 ? 'Up to date' : '$n new or updated');
      }
    } on Exception catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: 'Couldn’t read Health Connect: $e');
    }
  }

  /// Imports at most once an hour; Workout calls it once when it opens.
  Future<void> importIfStale() async {
    if (!state.supported || state.busy) return;
    final last = state.lastImport;
    if (last != null && AppClock.now().difference(last) < const Duration(hours: 1)) return;
    await check();
    if (state.granted) await importNow();
  }
}
