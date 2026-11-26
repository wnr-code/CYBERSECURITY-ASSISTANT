import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

import 'local_ai_artifact_status.dart' as artifact_status;
import 'local_ai_inference_runtime.dart';

/// Exact, immutable model metadata supplied for the Qwen official repository.
/// The hash validates these bytes against this pin; it is not a guarantee that
/// the model is free of all security or quality risks.
class LocalAiModelManifest {
  static const bool qwenArtifactIndependentlyVerified = artifact_status.qwenArtifactIndependentlyVerified;

  const LocalAiModelManifest({
    required this.repository,
    required this.revision,
    required this.fileName,
    required this.license,
    required this.fileSizeBytes,
    required this.sha256Hex,
    required this.downloadUrl,
  });

  static const qwenQ4Km = LocalAiModelManifest(
    repository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
    revision: 'dd26da440ef0330c47919d1ecae0966d24022222',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    license: 'Apache-2.0',
    fileSizeBytes: 1_117_320_736,
    sha256Hex: '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
    downloadUrl: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/dd26da440ef0330c47919d1ecae0966d24022222/qwen2.5-1.5b-instruct-q4_k_m.gguf',
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

/// Imports a user-downloaded GGUF into app-private storage. The selected file
/// is streamed to a temporary file, with the byte count and SHA-256 checked
/// before the final name is created or native inference is invoked.
class LocalAiModelInstaller {
  LocalAiModelInstaller({
    this.manifest = LocalAiModelManifest.qwenQ4Km,
    bool testOnlyAllowUnverifiedManifest = false,
    Future<XFile?> Function()? pickFile,
    Future<Directory> Function()? supportDirectory,
    Future<void> Function(String fileName, String sha256Hex)? loadModel,
  })  : _pickFile = pickFile ?? _pickGguf,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _loadModel = loadModel ?? const AndroidLlamaCppInferenceRuntime().loadVerifiedModel,
        _allowUnverifiedManifestForTests = testOnlyAllowUnverifiedManifest;

  final LocalAiModelManifest manifest;
  final Future<XFile?> Function() _pickFile;
  final Future<Directory> Function() _supportDirectory;
  final Future<void> Function(String fileName, String sha256Hex) _loadModel;
  final bool _allowUnverifiedManifestForTests;

  bool get _artifactPinApproved =>
      LocalAiModelManifest.qwenArtifactIndependentlyVerified || _allowUnverifiedManifestForTests;

  static Future<XFile?> _pickGguf() => openFile(
        acceptedTypeGroups: const [XTypeGroup(label: 'GGUF model', extensions: ['gguf'])],
      );

  Future<VerifiedLocalAiModel?> chooseVerifyAndLoad() async {
    if (!_artifactPinApproved) {
      throw const LocalAiModelInstallException('The Qwen artifact pin has not been independently verified against publisher metadata and actual GGUF bytes. Import and native loading are disabled.');
    }
    final selected = await _pickFile();
    if (selected == null) return null;
    return verifyAndLoadStream(fileName: selected.name, source: selected.openRead());
  }

  /// Exposed for deterministic tests with small injected manifests; production
  /// always uses [LocalAiModelManifest.qwenQ4Km].
  Future<VerifiedLocalAiModel> verifyAndLoadStream({required String fileName, required Stream<List<int>> source}) async {
    if (!_artifactPinApproved) {
      throw const LocalAiModelInstallException('The Qwen artifact pin has not been independently verified against publisher metadata and actual GGUF bytes. Import and native loading are disabled.');
    }
    if (fileName != manifest.fileName) {
      throw LocalAiModelInstallException('Wrong model filename. Select exactly ${manifest.fileName} from the pinned Qwen repository.');
    }
    if (manifest.fileSizeBytes <= 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(manifest.sha256Hex)) {
      throw const LocalAiModelInstallException('The app-owned model pin is invalid; installation was stopped.');
    }

    final support = await _supportDirectory();
    final modelDirectory = Directory(paths.join(support.path, 'local_ai', 'models'));
    await modelDirectory.create(recursive: true);
    final finalFile = File(paths.join(modelDirectory.path, manifest.fileName));
    final temporaryFile = File('${finalFile.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    var byteCount = 0;
    final sink = temporaryFile.openWrite(mode: FileMode.writeOnly);

    try {
      await for (final chunk in source) {
        byteCount += chunk.length;
        if (byteCount > manifest.fileSizeBytes) {
          throw LocalAiModelInstallException('Selected model exceeds the pinned size of ${manifest.fileSizeBytes} bytes; temporary data will be removed.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try { await sink.close(); } catch (_) {}
      try { if (await temporaryFile.exists()) await temporaryFile.delete(); } catch (_) {}
      rethrow;
    }

    late final String actualSha256;
    try {
      actualSha256 = (await sha256.bind(temporaryFile.openRead()).first).toString();
    } catch (error) {
      try { await temporaryFile.delete(); } catch (_) {}
      throw LocalAiModelInstallException('Could not read the copied model to verify its SHA-256; temporary file removed. ${error.toString().replaceAll(RegExp(r'\\s+'), ' ')}');
    }
    if (byteCount != manifest.fileSizeBytes || actualSha256 != manifest.sha256Hex) {
      try { await temporaryFile.delete(); } catch (_) {}
      throw LocalAiModelInstallException(
        'Model verification failed; temporary file removed. Expected ${manifest.fileSizeBytes} bytes and SHA-256 ${manifest.sha256Hex}; received $byteCount bytes and SHA-256 $actualSha256. No model was loaded.',
      );
    }

    if (await finalFile.exists()) await finalFile.delete();
    await temporaryFile.rename(finalFile.path);
    try {
      await _loadModel(manifest.fileName, manifest.sha256Hex);
    } catch (error) {
      final normalizedError = error.toString().replaceAll(RegExp(r'\s+'), ' ');
      throw LocalAiModelInstallException('The model file passed size and SHA-256 verification but native loading failed: ${normalizedError.substring(0, normalizedError.length.clamp(0, 240).toInt())}. The verified file remains in app-private storage for diagnosis.');
    }
    return VerifiedLocalAiModel(fileName: manifest.fileName, sizeBytes: byteCount, sha256Hex: actualSha256);
  }
}
