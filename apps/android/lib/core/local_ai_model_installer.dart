import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

import 'diagnostics.dart';
import 'local_ai_model_manifest.dart';
import 'local_ai_model_source.dart';
import 'local_ai_inference_runtime.dart';

export 'local_ai_model_manifest.dart';

enum LocalAiInstallPhase { checkingPublisher, downloading, verifying, loading, complete, failed }

class LocalAiInstallProgress {
  const LocalAiInstallProgress({required this.phase, this.bytesReceived = 0, this.totalBytes = 0});
  final LocalAiInstallPhase phase;
  final int bytesReceived;
  final int totalBytes;

  double? get fraction => phase == LocalAiInstallPhase.downloading && totalBytes > 0
      ? (bytesReceived / totalBytes).clamp(0.0, 1.0)
      : null;
}

typedef LocalAiProgressCallback = void Function(LocalAiInstallProgress progress);

/// Imports an exact pinned model for tests, and downloads the production Qwen
/// artifact only after live verification against the official Hub API.
class LocalAiModelInstaller {
  LocalAiModelInstaller({
    this.manifest = LocalAiModelManifest.qwenQ4Km,
    bool testOnlyAllowUnverifiedManifest = false,
    Future<XFile?> Function()? pickFile,
    Future<Directory> Function()? supportDirectory,
    Future<void> Function(String fileName, String sha256Hex, LocalAiPublisherFile publisherFile)? loadModel,
    LocalAiArtifactSource? artifactSource,
    Future<int?> Function()? availableStorageBytes,
  })  : _pickFile = pickFile ?? _pickGguf,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _loadModel = loadModel ?? const AndroidLlamaCppInferenceRuntime().loadVerifiedModel,
        _artifactSource = artifactSource ?? HuggingFaceLocalAiArtifactSource(),
        _availableStorageBytes = availableStorageBytes ?? _readAvailableStorageBytes,
        _allowUnverifiedManifestForTests = testOnlyAllowUnverifiedManifest;

  final LocalAiModelManifest manifest;
  final Future<XFile?> Function() _pickFile;
  final Future<Directory> Function() _supportDirectory;
  final Future<void> Function(String fileName, String sha256Hex, LocalAiPublisherFile publisherFile) _loadModel;
  final LocalAiArtifactSource _artifactSource;
  final Future<int?> Function() _availableStorageBytes;
  final bool _allowUnverifiedManifestForTests;

  bool get _legacyImportAllowed => _allowUnverifiedManifestForTests;

  static Future<int?> _readAvailableStorageBytes() async {
    try {
      final result = await const MethodChannel('org.cybersecurityassistant/local_ai_capabilities')
          .invokeMapMethod<Object?, Object?>('getDeviceCapabilities')
          .timeout(const Duration(seconds: 3));
      final available = result?['availableStorageBytes'];
      return available is int && available > 0 ? available : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static Future<XFile?> _pickGguf() => openFile(
        acceptedTypeGroups: const [XTypeGroup(label: 'GGUF model', extensions: ['gguf'])],
      );

  /// Restores a previously verified app-private model from its native receipt.
  /// The native bridge rechecks the receipt against this APK's static pin and
  /// hashes the entire file before loading, so restoring works offline.
  Future<VerifiedLocalAiModel?> restoreVerifiedInstalledModel() async {
    try {
      final status = await const MethodChannel('org.cybersecurityassistant/local_ai_runtime')
          .invokeMapMethod<Object?, Object?>('getRuntimeStatus')
          .timeout(const Duration(seconds: 90));
      if (status?['modelLoaded'] == true && status?['publisherMetadataVerified'] == true &&
          status?['modelName'] == manifest.fileName && status?['modelSha256'] == manifest.sha256Hex) {
        return VerifiedLocalAiModel(fileName: manifest.fileName, sizeBytes: manifest.fileSizeBytes, sha256Hex: manifest.sha256Hex);
      }
    } catch (_) {
      // Missing/old native runtime is handled by the regular pinned download path.
    }
    return null;
  }

  Future<bool> hasInstalledModelFile() async {
    final support = await _supportDirectory();
    return File(paths.join(support.path, 'local_ai', 'models', manifest.fileName)).exists();
  }

  Future<bool> hasPartialDownload() async {
    final support = await _supportDirectory();
    return File(paths.join(support.path, 'local_ai', 'models', '${manifest.fileName}.part')).exists();
  }

  Future<bool> hasLocalModelData() async => await hasInstalledModelFile() || await hasPartialDownload();

  Future<bool> deleteInstalledModel() async =>
      await const MethodChannel('org.cybersecurityassistant/local_ai_runtime').invokeMethod<bool>('deleteInstalledModel') ?? false;

  /// Downloads from Hugging Face after checking the immutable model record,
  /// then hashes the complete private file before native loading.
  Future<VerifiedLocalAiModel> downloadVerifyAndLoad({LocalAiProgressCallback? onProgress}) async {
    _emit(onProgress, const LocalAiInstallProgress(phase: LocalAiInstallPhase.checkingPublisher));
    LocalAiDownloadResponse? response;
    File? temporaryFile;
    RandomAccessFile? sink;
    var discardPartial = false;
    var phase = LocalAiInstallPhase.checkingPublisher;
    try {
      final isPinnedQwen = manifest.repository == LocalAiModelManifest.qwenQ4Km.repository &&
          manifest.revision == LocalAiModelManifest.qwenQ4Km.revision &&
          manifest.fileName == LocalAiModelManifest.qwenQ4Km.fileName &&
          manifest.license == LocalAiModelManifest.qwenQ4Km.license &&
          manifest.fileSizeBytes == LocalAiModelManifest.qwenQ4Km.fileSizeBytes &&
          manifest.sha256Hex == LocalAiModelManifest.qwenQ4Km.sha256Hex &&
          manifest.downloadUrl == LocalAiModelManifest.qwenQ4Km.downloadUrl;
      if (!isPinnedQwen && !_allowUnverifiedManifestForTests) {
        throw const LocalAiModelInstallException('Only the app-pinned Qwen candidate is enabled for this on-device installation flow.');
      }
      _validateManifestPin();
      final publisherFile = await _artifactSource.fetchPublisherMetadata(manifest);
      if (publisherFile.repository != manifest.repository || publisherFile.author != manifest.repository.split('/').first ||
          publisherFile.revision != manifest.revision || publisherFile.license.toLowerCase() != manifest.license.toLowerCase() ||
          publisherFile.fileName != manifest.fileName || publisherFile.sizeBytes != manifest.fileSizeBytes ||
          publisherFile.sha256Hex != manifest.sha256Hex) {
        throw const LocalAiModelInstallException('Official publisher metadata did not match every app-pinned model field. Installation was blocked.');
      }

      final support = await _supportDirectory();
      final modelDirectory = Directory(paths.join(support.path, 'local_ai', 'models'));
      await modelDirectory.create(recursive: true);
      final finalFile = File(paths.join(modelDirectory.path, manifest.fileName));

      phase = LocalAiInstallPhase.verifying;
      _emit(onProgress, LocalAiInstallProgress(phase: phase, totalBytes: manifest.fileSizeBytes));
      if (await finalFile.exists()) {
        final existingSize = await finalFile.length();
        if (existingSize == manifest.fileSizeBytes) {
          final existingSha = (await sha256.bind(finalFile.openRead()).first).toString();
          if (existingSha == publisherFile.sha256Hex && existingSha == manifest.sha256Hex) {
            phase = LocalAiInstallPhase.loading;
            _emit(onProgress, LocalAiInstallProgress(phase: phase, bytesReceived: existingSize, totalBytes: manifest.fileSizeBytes));
            await _loadPinnedModel(publisherFile);
            _emit(onProgress, LocalAiInstallProgress(phase: LocalAiInstallPhase.complete, bytesReceived: existingSize, totalBytes: manifest.fileSizeBytes));
            return VerifiedLocalAiModel(fileName: manifest.fileName, sizeBytes: existingSize, sha256Hex: existingSha);
          }
        }
        // Keep any pre-existing file until a fresh download has passed both
        // complete-size and complete-digest checks. The verified temp file
        // replaces it atomically below; failed retries preserve prior data.
      }

      temporaryFile = File('${finalFile.path}.part');
      if (await temporaryFile.exists() && await temporaryFile.length() > manifest.fileSizeBytes) {
        await temporaryFile.delete();
      }
      var byteCount = await temporaryFile.exists() ? await temporaryFile.length() : 0;
      if (byteCount == manifest.fileSizeBytes) {
        final partialSha = (await sha256.bind(temporaryFile.openRead()).first).toString();
        if (partialSha == publisherFile.sha256Hex && partialSha == manifest.sha256Hex) {
          phase = LocalAiInstallPhase.verifying;
        } else {
          await temporaryFile.delete();
          byteCount = 0;
        }
      }

      if (byteCount < manifest.fileSizeBytes) {
        final available = await _availableStorageBytes();
        const storageSafetyMargin = 64 * 1024 * 1024;
        final remainingBytes = manifest.fileSizeBytes - byteCount;
        if (available == null || available < remainingBytes + storageSafetyMargin) {
          throw const LocalAiModelInstallException('Free storage is unknown or insufficient for the remaining model bytes and a safety margin. The verified download checkpoint was kept.');
        }

        phase = LocalAiInstallPhase.downloading;
        const rangeChunkBytes = 64 * 1024 * 1024;
        const maxRangeAttempts = 5;
        _emit(onProgress, LocalAiInstallProgress(phase: phase, bytesReceived: byteCount, totalBytes: manifest.fileSizeBytes));
        while (byteCount < manifest.fileSizeBytes) {
          var rangeComplete = false;
          Object? lastRangeError;

          for (var attempt = 0; attempt < maxRangeAttempts && !rangeComplete; attempt++) {
            byteCount = await temporaryFile.exists() ? await temporaryFile.length() : 0;
            if (byteCount >= manifest.fileSizeBytes) {
              rangeComplete = byteCount == manifest.fileSizeBytes;
              break;
            }
            final rangeStart = byteCount;
            final rangeEnd = (rangeStart + rangeChunkBytes - 1).clamp(0, manifest.fileSizeBytes - 1).toInt();
            final expectedRangeLength = rangeEnd - rangeStart + 1;
            try {
              final chunkResponse = await _artifactSource.openPinnedDownload(
                manifest,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
              );
              response = chunkResponse;
              final expectedContentRange = 'bytes $rangeStart-$rangeEnd/${manifest.fileSizeBytes}';
              if (chunkResponse.statusCode != HttpStatus.partialContent || chunkResponse.contentRange != expectedContentRange ||
                  (chunkResponse.contentLength != null && chunkResponse.contentLength != expectedRangeLength)) {
                throw const LocalAiModelInstallException('Official source returned an invalid partial-download range. The saved checkpoint remains untrusted.');
              }

              final fileSink = await temporaryFile.open(mode: FileMode.append);
              sink = fileSink;
              var receivedInRange = 0;
              await for (final chunk in chunkResponse.body.timeout(const Duration(seconds: 90))) {
                if (receivedInRange + chunk.length > expectedRangeLength || byteCount + chunk.length > manifest.fileSizeBytes) {
                  discardPartial = true;
                  throw const LocalAiModelInstallException('Official source exceeded the requested model byte range. Partial data will be removed.');
                }
                await fileSink.writeFrom(chunk);
                receivedInRange += chunk.length;
                byteCount += chunk.length;
                _emit(onProgress, LocalAiInstallProgress(phase: phase, bytesReceived: byteCount, totalBytes: manifest.fileSizeBytes));
              }
              await fileSink.flush();
              if (receivedInRange != expectedRangeLength) {
                throw LocalAiModelInstallException('The model connection ended during byte range $rangeStart-$rangeEnd; $receivedInRange of $expectedRangeLength bytes arrived. The partial file was kept for resume.');
              }
              rangeComplete = true;
            } catch (error) {
              lastRangeError = error;
            } finally {
              try { await sink?.close(); } catch (_) {}
              sink = null;
              if (await temporaryFile.exists()) byteCount = await temporaryFile.length();
              try { await response?.dispose(); } catch (_) {}
              response = null;
            }
            if (!rangeComplete && attempt + 1 < maxRangeAttempts) {
              await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
            }
          }
          if (!rangeComplete) {
            if (lastRangeError is LocalAiModelInstallException) throw lastRangeError;
            throw const LocalAiModelInstallException('The model download was interrupted repeatedly. Its verified-size checkpoint was kept; retry to resume from the last byte.');
          }
        }
      }

      phase = LocalAiInstallPhase.verifying;
      final actualSize = await temporaryFile.length();
      if (actualSize != manifest.fileSizeBytes) {
        throw LocalAiModelInstallException('Downloaded file size verification failed: expected ${manifest.fileSizeBytes} bytes, received $actualSize bytes. The partial file was kept for resume.');
      }
      _emit(onProgress, LocalAiInstallProgress(phase: phase, bytesReceived: actualSize, totalBytes: manifest.fileSizeBytes));
      final actualSha256 = (await sha256.bind(temporaryFile.openRead()).first).toString();
      if (actualSha256 != publisherFile.sha256Hex || actualSha256 != manifest.sha256Hex) {
        discardPartial = true;
        throw const LocalAiModelInstallException('SHA-256 of the complete downloaded GGUF does not match both the official publisher metadata and app pin. Partial data will be removed.');
      }

      if (await finalFile.exists()) await finalFile.delete();
      await temporaryFile.rename(finalFile.path);
      temporaryFile = null;
      phase = LocalAiInstallPhase.loading;
      _emit(onProgress, LocalAiInstallProgress(phase: phase, bytesReceived: actualSize, totalBytes: manifest.fileSizeBytes));
      await _loadPinnedModel(publisherFile);
      _emit(onProgress, LocalAiInstallProgress(phase: LocalAiInstallPhase.complete, bytesReceived: actualSize, totalBytes: manifest.fileSizeBytes));
      return VerifiedLocalAiModel(fileName: manifest.fileName, sizeBytes: actualSize, sha256Hex: actualSha256);
    } catch (error) {
      try { await sink?.close(); } catch (_) {}
      if (temporaryFile != null) {
        try {
          if (await temporaryFile.exists() &&
              (discardPartial || await temporaryFile.length() > manifest.fileSizeBytes)) {
            await temporaryFile.delete();
          }
        } catch (_) {}
      }
      try { await response?.dispose(); } catch (_) {}
      _emit(onProgress, const LocalAiInstallProgress(phase: LocalAiInstallPhase.failed));
      await _recordLocalFailure(error, phase);
      if (error is LocalAiModelInstallException) rethrow;
      throw const LocalAiModelInstallException('Local AI installation failed safely. Check network/storage and retry; no unverified model was loaded.');
    }
  }

  Future<void> _loadPinnedModel(LocalAiPublisherFile publisherFile) async {
    try {
      await _loadModel(manifest.fileName, manifest.sha256Hex, publisherFile);
    } catch (error) {
      final safe = error.toString().replaceAll(RegExp(r'\s+'), ' ');
      throw LocalAiModelInstallException('The verified GGUF could not be loaded by the native runtime: ${safe.substring(0, safe.length.clamp(0, 220).toInt())}');
    }
  }

  Future<void> _recordLocalFailure(Object error, LocalAiInstallPhase phase) async {
    final reporter = DiagnosticReporter.active;
    if (reporter == null) return;
    try {
      await reporter.record(
        error,
        category: phase == LocalAiInstallPhase.checkingPublisher || phase == LocalAiInstallPhase.downloading
            ? DiagnosticCategory.network
            : phase == LocalAiInstallPhase.loading ? DiagnosticCategory.native : DiagnosticCategory.aiProvider,
        reportType: phase == LocalAiInstallPhase.loading ? DiagnosticReportType.crashReport : DiagnosticReportType.aiProviderError,
        component: 'local_ai_model_install',
        runtimeStatus: phase.name,
        reproductionSteps: 'Local AI download/verification/load failed. Model content and user prompts were not included.',
        requireManualReview: true,
      );
    } catch (_) {
      // The failure remains visible in the UI even if local diagnostic storage is unavailable.
    }
  }

  void _validateManifestPin() {
    if (manifest.fileSizeBytes <= 0 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(manifest.sha256Hex) ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(manifest.revision)) {
      throw const LocalAiModelInstallException('The app-owned model pin is malformed; installation was stopped.');
    }
  }

  void _emit(LocalAiProgressCallback? callback, LocalAiInstallProgress progress) {
    try { callback?.call(progress); } catch (_) {}
  }

  /// Legacy file-picker import is disabled in production. The supported
  /// on-device path downloads from and validates the pinned publisher source.
  Future<VerifiedLocalAiModel?> chooseVerifyAndLoad() async {
    if (!_legacyImportAllowed) {
      throw const LocalAiModelInstallException('File-picker model import is disabled. Use the verified official on-device download flow.');
    }
    final selected = await _pickFile();
    if (selected == null) return null;
    return verifyAndLoadStream(fileName: selected.name, source: selected.openRead());
  }

  /// Exposed for deterministic unit tests with injected small manifests only.
  Future<VerifiedLocalAiModel> verifyAndLoadStream({required String fileName, required Stream<List<int>> source}) async {
    if (!_legacyImportAllowed) {
      throw const LocalAiModelInstallException('Unverified file-picker import is disabled.');
    }
    if (fileName != manifest.fileName) throw LocalAiModelInstallException('Wrong model filename. Select exactly ${manifest.fileName}.');
    _validateManifestPin();
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
        if (byteCount > manifest.fileSizeBytes) throw const LocalAiModelInstallException('Selected model exceeds the pinned exact size.');
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try { await sink.close(); } catch (_) {}
      try { if (await temporaryFile.exists()) await temporaryFile.delete(); } catch (_) {}
      rethrow;
    }
    final actualSha256 = (await sha256.bind(temporaryFile.openRead()).first).toString();
    if (byteCount != manifest.fileSizeBytes || actualSha256 != manifest.sha256Hex) {
      try { await temporaryFile.delete(); } catch (_) {}
      throw const LocalAiModelInstallException('Test-file verification failed; exact size/SHA-256 mismatch.');
    }
    if (await finalFile.exists()) await finalFile.delete();
    await temporaryFile.rename(finalFile.path);
    await _loadModel(manifest.fileName, manifest.sha256Hex, LocalAiPublisherFile(
      repository: manifest.repository,
      author: manifest.repository.split('/').first,
      revision: manifest.revision,
      license: manifest.license,
      fileName: manifest.fileName,
      sizeBytes: byteCount,
      sha256Hex: actualSha256,
    ));
    return VerifiedLocalAiModel(fileName: manifest.fileName, sizeBytes: byteCount, sha256Hex: actualSha256);
  }
}
