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

@immutable
class ActivityImportState {
  const ActivityImportState({
    this.supported = false,
    this.available,
    this.granted = false,
    this.busy = false,
    this.lastImport,
    this.message,
    this.error,
  });

  /// This platform can read Health Connect (Android).
  final bool supported;

  /// Health Connect is installed (null until checked).
  final bool? available;
  final bool granted;
  final bool busy;
  final DateTime? lastImport;

  /// "3 new" after an import.
  final String? message;
  final String? error;

  ActivityImportState copyWith({
    bool? available,
    bool? granted,
    bool? busy,
    DateTime? lastImport,
    String? message,
    String? error,
    bool clearError = false,
  }) => ActivityImportState(
    supported: supported,
    available: available ?? this.available,
    granted: granted ?? this.granted,
    busy: busy ?? this.busy,
    lastImport: lastImport ?? this.lastImport,
    message: message ?? this.message,
    error: clearError ? null : error ?? this.error,
  );
}

class ActivityImportController extends Notifier<ActivityImportState> {
  HealthImport get _hc => ref.read(healthImportProvider);

  @override
  ActivityImportState build() => ActivityImportState(
    supported: Platform.isAndroid,
    lastImport: DateTime.tryParse(ref.read(prefsProvider).getString(DeviceKeys.activitiesImportedAt) ?? ''),
  );

  /// Reads whether Health Connect is there and allowed (cheap).
  Future<void> check() async {
    if (!state.supported) return;
    try {
      final available = await _hc.available();
      final granted = available && await _hc.granted();
      if (ref.mounted) state = state.copyWith(available: available, granted: granted);
    } on Exception catch (e) {
      if (ref.mounted) state = state.copyWith(available: false, error: 'Health Connect: $e');
    }
  }

  /// Asks for access, then imports.
  Future<void> connect() async {
    final ok = await _hc.requestAccess();
    if (!ref.mounted) return;
    state = state.copyWith(granted: ok);
    if (ok) await importNow();
  }

  Future<void> importNow() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
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

  /// Imports at most once an hour, when Workout opens.
  Future<void> importIfStale() async {
    if (!state.supported || state.busy) return;
    final last = state.lastImport;
    if (last != null && AppClock.now().difference(last) < const Duration(hours: 1)) return;
    await check();
    if (state.granted) await importNow();
  }
}
