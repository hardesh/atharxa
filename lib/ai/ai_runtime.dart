import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_llama/flutter_edge_ai_llama.dart';
import 'package:path/path.dart' as p;

import 'ai_models.dart';
import 'device_info.dart';

/// A failure the UI can show as is.
class AiException implements Exception {
  const AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cancels a running download.
class AiCancel {
  final _token = CancelToken();
  void cancel() => _token.cancel('Cancelled');
  bool get cancelled => _token.isCancelled;
}

/// One conversation with the loaded model; it keeps its own history.
abstract interface class AiConversation {
  /// Sends [text] and streams the reply's text as it is generated.
  Stream<String> send(String text);
  Future<void> stop();
  Future<void> close();
}

/// The on-device model runtime. The app talks to models only through this,
/// so the engines behind it can change without touching screens.
abstract interface class AiRuntime {
  /// RAM, chip and free space where models are stored.
  Future<DeviceCapabilities> deviceCapabilities();

  /// File names of installed models (catalog downloads and imports).
  Future<Set<String>> installedFiles();

  /// Model files the user imported.
  Future<List<AiModel>> importedModels();

  /// Downloads [m], reporting 0–1, then checks its SHA-256.
  Future<void> download(AiModel m, {required void Function(double) onProgress, required AiCancel cancel});

  /// Copies a model file the user picked into app storage; returns its model.
  Future<AiModel> importFile(String path);
  Future<void> remove(AiModel m);

  /// Loads [m] (unloading any other) and returns where it runs.
  Future<AiBackend?> load(AiModel m);

  /// Opens a conversation on the loaded model.
  Future<AiConversation> open({String? system});

  /// Frees the loaded model's memory.
  Future<void> unload();
}

/// [AiRuntime] on flutter_edge_ai: LiteRT-LM for `.litertlm`, llama.cpp
/// (llamadart) for `.gguf`.
class EdgeAiRuntime implements AiRuntime {
  Future<void>? _ready;
  InferenceModel? _model;
  String? _loadedId;

  Future<void> _init() =>
      _ready ??= FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine(), LlamaEngineProvider()]);

  static ModelType _type(AiModel m) => switch (m.family) {
    AiFamily.gemma => ModelType.gemma4,
    AiFamily.qwen => ModelType.qwen35,
    AiFamily.other => ModelType.general,
  };

  static ModelFileType _fileType(AiModel m) =>
      m.engine == AiEngine.litert ? ModelFileType.litertlm : ModelFileType.gguf;

  InferenceInstallationBuilder _builder(AiModel m) {
    final b = FlutterEdgeAi.installModel(modelType: _type(m), fileType: _fileType(m));
    if (m.imported) return b.fromFile(_importPath(m.fileName));
    // Android: a foreground download (with a progress notification) is not
    // stopped by the OS during a multi-gigabyte transfer.
    return b.fromNetwork(
      m.url!,
      filename: m.fileName,
      expectedSize: m.sizeBytes,
      foreground: Platform.isAndroid ? true : null,
    );
  }

  String? _importDir;
  String _importPath(String fileName) => p.join(_importDir!, fileName);

  @override
  Future<DeviceCapabilities> deviceCapabilities() async => readDeviceCapabilities(await modelDir());

  /// Where [m]'s file is stored.
  Future<String> modelFilePath(AiModel m) async {
    await modelDir();
    return m.imported ? _importPath(m.fileName) : FlutterEdgeAi.getModelPath(m.fileName);
  }

  /// Folder model files live in.
  Future<String> modelDir() async {
    await _init();
    final dir = p.dirname(await FlutterEdgeAi.getModelPath('probe.bin'));
    _importDir ??= p.join(dir, 'imported');
    return dir;
  }

  @override
  Future<Set<String>> installedFiles() async {
    await modelDir();
    return {...await FlutterEdgeAi.listInstalledModels(), for (final m in await importedModels()) m.fileName};
  }

  @override
  Future<List<AiModel>> importedModels() async {
    await modelDir();
    final dir = Directory(_importDir!);
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync().whereType<File>())
        if (AiModel.isModelFile(p.basename(f.path))) AiModel.imported(p.basename(f.path), f.lengthSync()),
    ];
  }

  @override
  Future<void> download(AiModel m, {required void Function(double) onProgress, required AiCancel cancel}) async {
    await _init();
    try {
      await _builder(
        m,
      ).withProgress((pct) => onProgress(pct / 100)).withCancelToken(cancel._token).install(activate: false);
    } on DownloadCancelledException {
      throw const AiException('Download cancelled');
    } on ModelValidationException {
      throw const AiException('The download was incomplete. Try again.');
    } on DownloadException catch (e) {
      throw AiException('Download failed: ${e.error}');
    }
    // The engine already checked the exact size. A full SHA-256 pass is
    // cheap on a desktop (≈18 s for 2.6 GB) but takes minutes on a phone, and
    // Android freezes it once the app is in the background, so phones rely
    // on the size check (and HTTPS from a pinned revision).
    final want = m.sha256;
    if (want == null || Platform.isAndroid || Platform.isIOS) return;
    final path = await modelFilePath(m);
    final got = await Isolate.run(() => sha256OfFile(path));
    if (got != want) {
      await FlutterEdgeAi.uninstallModel(m.fileName);
      throw const AiException('The downloaded file was damaged and has been removed. Try again.');
    }
  }

  @override
  Future<AiModel> importFile(String path) async {
    await modelDir();
    final name = p.basename(path);
    if (!AiModel.isModelFile(name)) throw const AiException('Pick a .gguf or .litertlm model file.');
    await Directory(_importDir!).create(recursive: true);
    final copy = await File(path).copy(_importPath(name));
    return AiModel.imported(name, await copy.length());
  }

  @override
  Future<void> remove(AiModel m) async {
    await modelDir();
    if (_loadedId == m.id) await unload();
    if (await FlutterEdgeAi.isModelInstalled(m.fileName)) await FlutterEdgeAi.uninstallModel(m.fileName);
    // An imported file is used in place, so uninstalling leaves our copy.
    final copy = File(_importPath(m.fileName));
    if (m.imported && copy.existsSync()) await copy.delete();
  }

  @override
  Future<AiBackend?> load(AiModel m) async {
    await modelDir();
    final current = _model;
    if (_loadedId == m.id && current != null && !current.isClosed) return _backend(current);
    // Re-installing an installed file only makes it the active model.
    await _builder(m).install();
    final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final model = await FlutterEdgeAi.getActiveModel(
      maxTokens: m.contextTokens,
      preferredBackend: switch (m.backend) {
        AiBackend.npu => PreferredBackend.npu,
        AiBackend.gpu => PreferredBackend.gpu,
        AiBackend.cpu => PreferredBackend.cpu,
        null => null,
      },
      // Half precision on the GPU can mangle copied numbers (dates, amounts);
      // the Mac has the memory for full precision.
      activationDataType: desktop && m.engine == AiEngine.litert ? ActivationDataType.float32 : null,
    );
    _model = model;
    _loadedId = m.id;
    return _backend(model);
  }

  static AiBackend? _backend(InferenceModel m) => switch (m.activeBackend) {
    PreferredBackend.npu => AiBackend.npu,
    PreferredBackend.gpu => AiBackend.gpu,
    PreferredBackend.cpu => AiBackend.cpu,
    _ => null,
  };

  @override
  Future<AiConversation> open({String? system}) async {
    final model = _model;
    if (model == null || model.isClosed) throw const AiException('No model loaded');
    return _EdgeConversation(await model.openChat(systemInstruction: system, maxOutputTokens: 1024));
  }

  @override
  Future<void> unload() async {
    final m = _model;
    _model = null;
    _loadedId = null;
    if (m != null && !m.isClosed) await m.close();
  }
}

class _EdgeConversation implements AiConversation {
  _EdgeConversation(this._chat);
  final InferenceChat _chat;

  @override
  Stream<String> send(String text) async* {
    await _chat.addQueryChunk(Message(text: text, isUser: true));
    await for (final r in _chat.generateChatResponseAsync()) {
      if (r is TextResponse) yield r.token;
    }
  }

  @override
  Future<void> stop() => _chat.stopGeneration();

  @override
  Future<void> close() => _chat.close();
}

/// Hex SHA-256 of a (multi-gigabyte) file, streamed.
Future<String> sha256OfFile(String path) async => (await sha256.bind(File(path).openRead()).first).toString();
