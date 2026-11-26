/// App-owned immutable catalog of Local AI GGUF files. Publisher metadata is
/// checked at install time, and the complete local file is SHA-256 verified
/// before it is handed to the native loader. A pin is an identity check, not
/// proof that model behavior is harmless.
class LocalAiModelManifest {
  const LocalAiModelManifest({
    required this.id,
    required this.displayName,
    required this.summary,
    required this.repository,
    required this.revision,
    required this.fileName,
    required this.license,
    required this.fileSizeBytes,
    required this.sha256Hex,
    required this.downloadUrl,
    this.licenseRepository = '',
    this.licenseRevision = '',
  });

  final String id;
  final String displayName;
  final String summary;
  final String repository;
  final String revision;
  final String fileName;
  final String license;
  final int fileSizeBytes;
  final String sha256Hex;
  final String downloadUrl;
  final String licenseRepository;
  final String licenseRevision;

  static const qwenQ4Km = LocalAiModelManifest(
    id: 'qwen25-15b-q4km',
    displayName: 'Qwen2.5 1.5B Instruct · Q4_K_M',
    summary: 'Kandidat utama; ukuran menengah dan mengikuti pin Qwen yang diberikan.',
    repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
    revision: 'dd26da440ef0330c47919d1ecae0966d24022222',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    license: 'Apache-2.0',
    fileSizeBytes: 1_117_320_736,
    sha256Hex: '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
    downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/dd26da440ef0330c47919d1ecae0966d24022222/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    licenseRepository: 'Qwen/Qwen2.5-1.5B-Instruct',
    licenseRevision: '989aa7980e4cf806f80c7fef2b1adb7bc71aa306',
  );

  static const qwen05Q4Km = LocalAiModelManifest(
    id: 'qwen25-05b-q4km',
    displayName: 'Qwen2.5 0.5B Instruct · Q4_K_M',
    summary: 'Pilihan paling ringan untuk perangkat dengan batas memori lebih ketat.',
    repository: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
    revision: '6dd44a1fb35d11b5d1b28902876ce3cc9e882d0e',
    fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    license: 'Apache-2.0',
    fileSizeBytes: 491_400_032,
    sha256Hex: '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db',
    downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/6dd44a1fb35d11b5d1b28902876ce3cc9e882d0e/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    licenseRepository: 'Qwen/Qwen2.5-0.5B-Instruct',
    licenseRevision: '7ae557604adf67be50417f59c2c2f167def9a775',
  );

  static const smolLm2Q4Km = LocalAiModelManifest(
    id: 'smollm2-17b-q4km',
    displayName: 'SmolLM2 1.7B Instruct · Q4_K_M',
    summary: 'Kandidat pembanding Hugging Face untuk uji kemampuan dan kompatibilitas.',
    repository: 'HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF',
    revision: '6a7e79393ef2957e087f11fce1e50476799e313c',
    fileName: 'smollm2-1.7b-instruct-q4_k_m.gguf',
    license: 'Apache-2.0',
    fileSizeBytes: 1_055_609_536,
    sha256Hex: 'decd2598bc2c8ed08c19adc3c8fdd461ee19ed5708679d1c54ef54a5a30d4f33',
    downloadUrl: 'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/6a7e79393ef2957e087f11fce1e50476799e313c/smollm2-1.7b-instruct-q4_k_m.gguf',
    licenseRepository: 'HuggingFaceTB/SmolLM2-1.7B-Instruct',
    licenseRevision: '31b70e2e869a7173562077fd711b654946d38674',
  );

  static const candidates = <LocalAiModelManifest>[qwenQ4Km, qwen05Q4Km, smolLm2Q4Km];
  // Publisher API LFS metadata is pinned, but no full artifact was downloaded
  // independently in this workspace. Runtime still hashes the complete file.
  static const bool qwenArtifactIndependentlyVerified = false;
}

class LocalAiModelInstallException implements Exception {
  const LocalAiModelInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VerifiedLocalAiModel {
  const VerifiedLocalAiModel({required this.fileName, required this.sizeBytes, required this.sha256Hex});
  final String fileName;
  final int sizeBytes;
  final String sha256Hex;
}
