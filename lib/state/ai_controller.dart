import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_models.dart';
import '../ai/assistant_context.dart';
import '../ai/ai_runtime.dart';
import 'core_providers.dart';

/// The on-device model runtime; tests override it with a fake.
final aiRuntimeProvider = Provider<AiRuntime>((ref) => EdgeAiRuntime());

/// AI models on this device (You › AI models, the assistant's model picker).
/// Kept alive so downloads continue when the page closes; models load only
/// while the assistant is open and are freed a minute after it closes.
final aiProvider = NotifierProvider<AiController, AiState>(AiController.new);

@immutable
class AiState {
  const AiState({
    this.ready = false,
    this.caps,
    this.installed = const {},
    this.imported = const [],
    this.chosenId,
    this.downloads = const {},
    this.errors = const {},
    this.wifiOnly = true,
    this.scopes = const {},
    this.loadedId,
    this.backend,
    this.readyId,
    this.interruptedId,
  });

  /// Device facts and installed files have been read.
  final bool ready;
  final DeviceCapabilities? caps;
  final Set<String> installed;
  final List<AiModel> imported;
  final String? chosenId;

  /// Download progress (0–1) by model id.
  final Map<String, double> downloads;
  final Map<String, String> errors;
  final bool wifiOnly;

  /// What the assistant may read (per device).
  final Set<AiScope> scopes;

  /// The model in memory and where it runs.
  final String? loadedId;
  final AiBackend? backend;

  /// A model that just finished downloading ("… is ready"), until dismissed.
  final String? readyId;

  /// A download the app was closed during, offered for resuming.
  final String? interruptedId;

  /// A catalog or imported model by id.
  AiModel? model(String? id) => id == null ? null : [...aiCatalog, ...imported].where((m) => m.id == id).firstOrNull;

  /// Catalog models offered here (not another chip's NPU build, not retired).
  List<AiModel> get catalog => [
    for (final m in aiCatalog)
      if (!m.retired && (caps == null || fitFor(m, caps!) != AiFit.otherChip)) m,
  ];

  List<AiModel> get installedModels => [
    for (final m in [...aiCatalog, ...imported])
      if (installed.contains(m.fileName)) m,
  ];

  List<AiModel> get available => [
    for (final m in catalog)
      if (!installed.contains(m.fileName)) m,
  ];

  /// The model chats use: the chosen one, else the first installed.
  AiModel? get active {
    final models = installedModels;
    return models.where((m) => m.id == chosenId).firstOrNull ?? models.firstOrNull;
  }

  AiState copyWith({
    bool? ready,
    DeviceCapabilities? caps,
    Set<String>? installed,
    List<AiModel>? imported,
    String? chosenId,
    Map<String, double>? downloads,
    Map<String, String>? errors,
    bool? wifiOnly,
    Set<AiScope>? scopes,
    String? loadedId,
    AiBackend? backend,
    bool unloaded = false,
    String? readyId,
    bool clearReady = false,
    String? interruptedId,
    bool clearInterrupted = false,
  }) => AiState(
    ready: ready ?? this.ready,
    caps: caps ?? this.caps,
    installed: installed ?? this.installed,
    imported: imported ?? this.imported,
    chosenId: chosenId ?? this.chosenId,
    downloads: downloads ?? this.downloads,
    errors: errors ?? this.errors,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    scopes: scopes ?? this.scopes,
    loadedId: unloaded ? null : loadedId ?? this.loadedId,
    backend: unloaded ? null : backend ?? this.backend,
    readyId: clearReady ? null : readyId ?? this.readyId,
    interruptedId: clearInterrupted ? null : interruptedId ?? this.interruptedId,
  );
}

class AiController extends Notifier<AiState> {
  final _cancels = <String, AiCancel>{};
  Timer? _release;

  AiRuntime get _rt => ref.read(aiRuntimeProvider);

  @override
  AiState build() {
    final prefs = ref.read(prefsProvider);
    ref.onDispose(() => _release?.cancel());
    return AiState(
      chosenId: prefs.getString(DeviceKeys.aiModel),
      wifiOnly: prefs.getBool(DeviceKeys.aiWifiOnly) ?? true,
      scopes: AiScope.parse(prefs.getStringList(DeviceKeys.aiScopes)),
      interruptedId: prefs.getString(DeviceKeys.aiPendingDownload),
    );
  }

  /// Reads device facts and what is installed (cheap; safe to repeat).
  Future<void> refresh() async {
    final (caps, files, imported) = await (_rt.deviceCapabilities(), _rt.installedFiles(), _rt.importedModels()).wait;
    state = state.copyWith(ready: true, caps: caps, installed: files, imported: imported);
  }

  Future<void> setWifiOnly(bool on) async {
    await ref.read(prefsProvider).setBool(DeviceKeys.aiWifiOnly, on);
    state = state.copyWith(wifiOnly: on);
  }

  Future<void> setScope(AiScope scope, bool on) async {
    final scopes = {...state.scopes};
    on ? scopes.add(scope) : scopes.remove(scope);
    await ref.read(prefsProvider).setStringList(DeviceKeys.aiScopes, [for (final s in scopes) s.name]);
    state = state.copyWith(scopes: scopes);
  }

  Future<void> choose(AiModel m) async {
    await ref.read(prefsProvider).setString(DeviceKeys.aiModel, m.id);
    state = state.copyWith(chosenId: m.id);
  }

  /// Starts downloading [m]. Returns a reason when it can't start.
  Future<String?> download(AiModel m) async {
    if (state.downloads.containsKey(m.id)) return null;
    if (state.wifiOnly && !await _onWifi()) return 'Connect to Wi-Fi, or allow downloads on mobile data';
    final free = state.caps?.freeBytes;
    if (free != null && free < m.sizeBytes * 1.1) return 'Not enough free space for ${m.name}';
    final cancel = _cancels[m.id] = AiCancel();
    final prefs = ref.read(prefsProvider);
    // Remembered until it ends, so a download cut off by closing the app can
    // be offered again on the next start.
    await prefs.setString(DeviceKeys.aiPendingDownload, m.id);
    state = state.copyWith(
      downloads: {...state.downloads, m.id: 0},
      errors: {...state.errors}..remove(m.id),
      clearInterrupted: true,
      clearReady: true,
    );
    try {
      await _rt.download(
        m,
        cancel: cancel,
        onProgress: (p) {
          if (ref.mounted) state = state.copyWith(downloads: {...state.downloads, m.id: p});
        },
      );
      if (!ref.mounted) return null;
      state = state.copyWith(installed: {...state.installed, m.fileName}, readyId: m.id);
      if (state.installedModels.length == 1) await choose(m);
    } on Object catch (e) {
      final msg = e is AiException ? e.message : 'Download failed: $e';
      if (ref.mounted && !cancel.cancelled) state = state.copyWith(errors: {...state.errors, m.id: msg});
    } finally {
      _cancels.remove(m.id);
      await prefs.remove(DeviceKeys.aiPendingDownload);
      if (ref.mounted) state = state.copyWith(downloads: {...state.downloads}..remove(m.id));
    }
    return null;
  }

  void cancelDownload(AiModel m) => _cancels[m.id]?.cancel();

  /// Hides the "ready", "failed" and "stopped" notices.
  Future<void> dismissNotices() async {
    await ref.read(prefsProvider).remove(DeviceKeys.aiPendingDownload);
    state = state.copyWith(errors: const {}, clearReady: true, clearInterrupted: true);
  }

  Future<AiModel> import(String path) async {
    final m = await _rt.importFile(path);
    state = state.copyWith(
      installed: {...state.installed, m.fileName},
      imported: [...state.imported.where((x) => x.fileName != m.fileName), m],
    );
    await choose(m);
    return m;
  }

  Future<void> remove(AiModel m) async {
    await _rt.remove(m);
    state = state.copyWith(
      installed: {...state.installed}..remove(m.fileName),
      imported: state.imported.where((x) => x.id != m.id).toList(),
      unloaded: state.loadedId == m.id,
    );
  }

  /// Loads the active model (if not already) for the assistant.
  Future<AiModel> ensureLoaded() async {
    _release?.cancel();
    final m = state.active;
    if (m == null) throw const AiException('Download a model first');
    if (state.loadedId == m.id) return m;
    final backend = await _rt.load(m);
    state = state.copyWith(loadedId: m.id, backend: backend);
    return m;
  }

  /// Frees the model's memory a minute after the assistant closes.
  void releaseSoon() {
    _release?.cancel();
    if (!ref.mounted) return;
    _release = Timer(const Duration(minutes: 1), () async {
      await _rt.unload();
      if (ref.mounted) state = state.copyWith(unloaded: true);
    });
  }

  static Future<bool> _onWifi() async {
    final r = await Connectivity().checkConnectivity();
    return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
  }
}
