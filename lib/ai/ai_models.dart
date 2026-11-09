/// On-device AI models the app offers (DESIGN.md §7.6): what they are, where
/// each file comes from, and whether it suits this device.
///
/// Plain data, so the catalog and the fit rules are testable without an
/// engine. Every download is pinned to a Hugging Face commit with its size
/// and SHA-256; the file is checked after downloading.
library;

/// Which engine runs a model file.
enum AiEngine {
  /// Google LiteRT-LM (`.litertlm`): GPU on phones and the Mac, NPU builds.
  litert,

  /// llama.cpp (`.gguf`): CPU on phones, Metal on the Mac.
  llama,
}

enum AiFamily {
  gemma('Gemma 4', 'Google'),
  qwen('Qwen3.5', 'Alibaba'),
  other('Model', '');

  const AiFamily(this.label, this.maker);
  final String label, maker;
}

/// Where a model runs, as the engine reports it after loading.
enum AiBackend {
  npu('NPU'),
  gpu('GPU'),
  cpu('CPU');

  const AiBackend(this.label);
  final String label;
}

/// One model file the app can download (or one the user imported).
class AiModel {
  const AiModel({
    required this.id,
    required this.name,
    required this.family,
    required this.engine,
    required this.fileName,
    required this.sizeBytes,
    this.repo,
    this.revision,
    this.path,
    this.sha256,
    this.backend,
    this.npuChip,
    this.desktopOnly = false,
    this.note = '',
    this.contextTokens = 4096,
  });

  /// Stable id (stored as this device's chosen model).
  final String id;
  final String name;
  final AiFamily family;
  final AiEngine engine;

  /// The name the file is installed under.
  final String fileName;
  final int sizeBytes;

  /// Hugging Face source, pinned to a commit. Null for imported files.
  final String? repo, revision, path;
  final String? sha256;

  /// Backend to ask for first (null: the engine's default).
  final AiBackend? backend;

  /// A build compiled for one NPU runs only on that chip ("Tensor G5").
  final String? npuChip;

  /// Too large for any phone.
  final bool desktopOnly;
  final String note;

  /// Context window (prompt + history + reply), in tokens.
  final int contextTokens;

  bool get imported => repo == null;

  String? get url => repo == null
      ? null
      : 'https://huggingface.co/$repo/resolve/$revision/${path!.split('/').map(Uri.encodeComponent).join('/')}';

  /// A model file picked from disk ("My model.gguf").
  factory AiModel.imported(String fileName, int sizeBytes) {
    final lower = fileName.toLowerCase();
    return AiModel(
      id: 'file:$fileName',
      name: fileName.replaceFirst(RegExp(r'\.(gguf|litertlm)$', caseSensitive: false), ''),
      family: lower.contains('gemma')
          ? AiFamily.gemma
          : lower.contains('qwen')
          ? AiFamily.qwen
          : AiFamily.other,
      engine: lower.endsWith('.litertlm') ? AiEngine.litert : AiEngine.llama,
      fileName: fileName,
      sizeBytes: sizeBytes,
      note: 'Imported file',
    );
  }

  /// Whether [fileName] is a model file the engines can run.
  static bool isModelFile(String fileName) => RegExp(r'\.(gguf|litertlm)$', caseSensitive: false).hasMatch(fileName);
}

/// The catalog. Sizes and checksums are the published files' (Gemma
/// `.litertlm` builds match flutter_edge_ai_litertlm's pinned catalog).
const aiCatalog = <AiModel>[
  AiModel(
    id: 'gemma-4-e2b-npu-g5',
    name: 'Gemma 4 E2B · NPU',
    family: AiFamily.gemma,
    engine: AiEngine.litert,
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    revision: 'b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1',
    path: 'gemma-4-E2B-it_Google_Tensor_G5.litertlm',
    fileName: 'gemma-4-E2B-it_Google_Tensor_G5.litertlm',
    sha256: 'af1082986639ecde7db95d91be6fe54f8b6b458104734c5bafc204e69d6852dc',
    sizeBytes: 3113545589,
    backend: AiBackend.npu,
    npuChip: 'Tensor G5',
    note: 'Built for the Tensor G5 AI chip',
  ),
  AiModel(
    id: 'gemma-4-e2b',
    name: 'Gemma 4 E2B',
    family: AiFamily.gemma,
    engine: AiEngine.litert,
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    revision: 'b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1',
    path: 'gemma-4-E2B-it.litertlm',
    fileName: 'gemma-4-E2B-it.litertlm',
    sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
    sizeBytes: 2588147712,
    backend: AiBackend.gpu,
    note: 'Fast, good for everyday questions',
  ),
  AiModel(
    id: 'gemma-4-e4b',
    name: 'Gemma 4 E4B',
    family: AiFamily.gemma,
    engine: AiEngine.litert,
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    revision: '2eee7ac325f20eb8c9ac1d0e972f7c84663062da',
    path: 'gemma-4-E4B-it.litertlm',
    fileName: 'gemma-4-E4B-it.litertlm',
    sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
    sizeBytes: 3659530240,
    backend: AiBackend.gpu,
    note: 'Better answers, needs more memory',
  ),
  AiModel(
    id: 'gemma-4-12b',
    name: 'Gemma 4 12B',
    family: AiFamily.gemma,
    engine: AiEngine.llama,
    repo: 'google/gemma-4-12B-it-qat-q4_0-gguf',
    revision: '29d097773436b69ff9feafd636ab4cf873786537',
    path: 'gemma-4-12b-it-qat-q4_0.gguf',
    fileName: 'gemma-4-12b-it-qat-q4_0.gguf',
    sha256: '93567e57a8fe10b23569b9d9ec38cd005deedf71e29477c421a4b83f418a538b',
    sizeBytes: 6975879296,
    backend: AiBackend.gpu,
    desktopOnly: true,
    note: 'The most capable; Mac only',
  ),
  AiModel(
    id: 'qwen3.5-0.8b',
    name: 'Qwen3.5 0.8B',
    family: AiFamily.qwen,
    engine: AiEngine.llama,
    repo: 'unsloth/Qwen3.5-0.8B-GGUF',
    revision: '6ab461498e2023f6e3c1baea90a8f0fe38ab64d0',
    path: 'Qwen3.5-0.8B-Q4_K_M.gguf',
    fileName: 'Qwen3.5-0.8B-Q4_K_M.gguf',
    sha256: 'bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517',
    sizeBytes: 532517120,
    note: 'Tiny and quick; simple answers',
  ),
  AiModel(
    id: 'qwen3.5-2b',
    name: 'Qwen3.5 2B',
    family: AiFamily.qwen,
    engine: AiEngine.llama,
    repo: 'unsloth/Qwen3.5-2B-GGUF',
    revision: 'f6d5376be1edb4d416d56da11e5397a961aca8ae',
    path: 'Qwen3.5-2B-Q4_K_M.gguf',
    fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
    sha256: 'aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223',
    sizeBytes: 1280835840,
    note: 'Small; good on phones with 8 GB',
  ),
  AiModel(
    id: 'qwen3.5-4b',
    name: 'Qwen3.5 4B',
    family: AiFamily.qwen,
    engine: AiEngine.llama,
    repo: 'unsloth/Qwen3.5-4B-GGUF',
    revision: 'e87f176479d0855a907a41277aca2f8ee7a09523',
    path: 'Qwen3.5-4B-Q4_K_M.gguf',
    fileName: 'Qwen3.5-4B-Q4_K_M.gguf',
    sha256: '00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4',
    sizeBytes: 2740937888,
    note: 'Balanced',
  ),
  AiModel(
    id: 'qwen3.5-9b',
    name: 'Qwen3.5 9B',
    family: AiFamily.qwen,
    engine: AiEngine.llama,
    repo: 'unsloth/Qwen3.5-9B-GGUF',
    revision: '3885219b6810b007914f3a7950a8d1b469d598a5',
    path: 'Qwen3.5-9B-Q4_K_M.gguf',
    fileName: 'Qwen3.5-9B-Q4_K_M.gguf',
    sha256: '03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8',
    sizeBytes: 5680522464,
    backend: AiBackend.gpu,
    desktopOnly: true,
    note: 'Strong reasoning; Mac only',
  ),
];

/// What this device has, for "fits this device".
class DeviceCapabilities {
  const DeviceCapabilities({required this.desktop, this.ramBytes, this.chip, this.freeBytes});

  final bool desktop;

  /// Null when it could not be read.
  final int? ramBytes, freeBytes;
  final String? chip;

  /// RAM as sold ("12 GB"): rounded up to whole GiB.
  int? get ramGb => ramBytes == null ? null : (ramBytes! / (1 << 30)).ceil();

  /// Memory a model may use: phones keep room for the OS and other apps.
  int? get modelBudget => ramBytes == null ? null : (ramBytes! * (desktop ? 0.6 : 0.45)).round();
}

enum AiFit {
  fits,

  /// Loads, but may be slow or squeeze other apps out.
  tight,
  tooLarge,
  desktopOnly,

  /// An NPU build for another chip: not shown.
  otherChip,
}

/// Whether [m] suits device [d].
AiFit fitFor(AiModel m, DeviceCapabilities d) {
  if (m.npuChip != null && m.npuChip!.toLowerCase() != d.chip?.toLowerCase()) return AiFit.otherChip;
  if (m.desktopOnly && !d.desktop) return AiFit.desktopOnly;
  final budget = d.modelBudget;
  if (budget == null) return AiFit.fits;
  final need = m.sizeBytes * 1.2; // weights + context
  if (need <= budget) return AiFit.fits;
  if (need <= budget * 1.3) return AiFit.tight;
  return AiFit.tooLarge;
}

/// The catalog model to suggest first on [d]: the NPU build on its chip, else
/// the best model that fits.
AiModel? recommendedFor(DeviceCapabilities d) {
  const order = ['gemma-4-e2b-npu-g5', 'gemma-4-e4b', 'gemma-4-e2b', 'qwen3.5-2b', 'qwen3.5-0.8b'];
  final phoneOrder = order.where((id) => id != 'gemma-4-e4b');
  for (final id in d.desktop ? order : phoneOrder) {
    final m = aiCatalog.firstWhere((m) => m.id == id);
    if (fitFor(m, d) == AiFit.fits) return m;
  }
  return null;
}
