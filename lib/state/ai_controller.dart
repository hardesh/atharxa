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
    this.wifiOnly = true,
    this.scopes = const {},
    this.loadedId,
    this.backend,
    this.notice,
  });

  /// Device facts and installed files have been read.
  final bool ready;
  final DeviceCapabilities? caps;
  final Set<String> installed;
  final List<AiModel> imported;
  final String? chosenId;

  /// Download progress (0–1) by model id.
  final Map<String, double> downloads;
  final bool wifiOnly;

  /// What the assistant may read (per device).
  final Set<AiScope> scopes;

  /// The model in memory and where it runs.
  final String? loadedId;
  final AiBackend? backend;

  /// What the download banner says once a download has ended (until dismissed).
  final AiNotice? notice;

  /// Why [m]'s last download failed, if it did.
  String? errorFor(AiModel m) => switch (notice) {
    DownloadFailed(:final modelId, :final message) when modelId == m.id => message,
    _ => null,
  };

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
    bool? wifiOnly,
    Set<AiScope>? scopes,
    String? loadedId,
    AiBackend? backend,
    bool unloaded = false,
    AiNotice? notice,
    bool clearNotice = false,
  }) => AiState(
    ready: ready ?? this.ready,
    caps: caps ?? this.caps,
    installed: installed ?? this.installed,
    imported: imported ?? this.imported,
    chosenId: chosenId ?? this.chosenId,
    downloads: downloads ?? this.downloads,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    scopes: scopes ?? this.scopes,
    loadedId: unloaded ? null : loadedId ?? this.loadedId,
    backend: unloaded ? null : backend ?? this.backend,
    notice: clearNotice ? null : notice ?? this.notice,
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
      notice: switch (prefs.getString(DeviceKeys.aiPendingDownload)) {
        final String id => DownloadStopped(id),
        null => null,
      },
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
    state = state.copyWith(downloads: {...state.downloads, m.id: 0}, clearNotice: true);
    try {
      await _rt.download(
        m,
        cancel: cancel,
        onProgress: (p) {
          // Whole percents only: a multi-GB download would otherwise rebuild
          // the banner thousands of times.
          final pct = (p * 100).floor() / 100;
          if (ref.mounted && pct != state.downloads[m.id]) {
            state = state.copyWith(downloads: {...state.downloads, m.id: pct});
          }
        },
      );
      if (!ref.mounted) return null;
      state = state.copyWith(installed: {...state.installed, m.fileName}, notice: ModelReady(m.id));
      if (state.installedModels.length == 1) await choose(m);
    } on Object catch (e) {
      final msg = e is AiException ? e.message : 'Download failed: $e';
      if (ref.mounted && !cancel.cancelled) state = state.copyWith(notice: DownloadFailed(m.id, msg));
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
    state = state.copyWith(clearNotice: true);
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

/// How a model download ended, for the banner.
sealed class AiNotice {
  const AiNotice(this.modelId);
  final String modelId;
}

class ModelReady extends AiNotice {
  const ModelReady(super.modelId);
}

class DownloadFailed extends AiNotice {
  const DownloadFailed(super.modelId, this.message);
  final String message;
}

/// The app was closed before the download finished.
class DownloadStopped extends AiNotice {
  const DownloadStopped(super.modelId);
}
