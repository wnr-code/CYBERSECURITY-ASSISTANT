/// Immutable app pin for the first Local AI candidate. The app verifies these
/// expected values against the official Hugging Face API and actual bytes at
/// install time; these values alone do not establish provenance.
class LocalAiModelManifest {
  const LocalAiModelManifest({
    required this.repository,
    required this.revision,
    required this.fileName,
    required this.license,
    required this.fileSizeBytes,
    required this.sha256Hex,
    required this.downloadUrl,
  });

  /// No independent audit of the candidate's upstream pin is recorded in this
  /// source checkout. The APK still verifies live publisher metadata and the
  /// complete downloaded bytes before native load.
  static const bool qwenArtifactIndependentlyVerified = false;

  static const qwenQ4Km = LocalAiModelManifest(
    repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
    revision: '91cad51170dc346986eccefdc2dd33a9da36ead9',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    license: 'Apache-2.0',
    fileSizeBytes: 1_117_320_736,
    sha256Hex: '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
    downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf',
  );

  final String repository;
  final String revision;
  final String fileName;
  final String license;
  final int fileSizeBytes;
  final String sha256Hex;
  final String downloadUrl;
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
