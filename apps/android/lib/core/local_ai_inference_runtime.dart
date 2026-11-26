import 'dart:async';

import 'package:flutter/services.dart';

import 'ai_provider_manager.dart';
import 'local_ai_model_manifest.dart';
import 'local_ai_model_source.dart';

/// Flutter MethodChannel adapter for the Android arm64 llama.cpp JNI bridge.
/// It performs no networking; absent native code or a verified loaded model is
/// a hard Not Ready state, never a reason to select a cloud provider.
class AndroidLlamaCppInferenceRuntime implements LocalAiInferenceRuntime, LocalAiInferenceReadiness, LocalAiChatAvailability {
  const AndroidLlamaCppInferenceRuntime({
    this.channel = const MethodChannel('org.cybersecurityassistant/local_ai_runtime'),
  });

  static const sourceCommit = 'ea722948146befb23c9529c1ec7f59fb2f34911f';
  final MethodChannel channel;

  @override
  Future<bool> isReady() => _hasVerifiedLoadedModel(requireSuccessfulInference: true);

  @override
  Future<bool> canAttemptInference() => _hasVerifiedLoadedModel(requireSuccessfulInference: false);

  Future<bool> _hasVerifiedLoadedModel({required bool requireSuccessfulInference}) async {
    try {
      final status = await channel.invokeMapMethod<Object?, Object?>('getRuntimeStatus')
          .timeout(const Duration(seconds: 90));
      return status != null &&
          status['sourceCommit'] == sourceCommit &&
          status['runtimeLoaded'] == true &&
          status['modelLoaded'] == true &&
          status['publisherMetadataVerified'] == true &&
          (!requireSuccessfulInference || (status['inferenceSucceeded'] == true && status['offlineInferenceSucceeded'] == true)) &&
          LocalAiModelManifest.candidates.any((manifest) =>
              status['modelName'] == manifest.fileName && status['modelSha256'] == manifest.sha256Hex) &&
          status['abi'] == 'arm64-v8a' &&
          status['backend'] == 'cpu' &&
          status['modelName'] is String &&
          (status['modelSha256'] is String) &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(status['modelSha256'] as String);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> loadVerifiedModel(String fileName, String sha256Hex, LocalAiPublisherFile publisherFile) async {
    final manifest = LocalAiModelManifest.candidates.where((candidate) =>
        candidate.fileName == fileName && candidate.sha256Hex == sha256Hex &&
        candidate.repository == publisherFile.repository && candidate.revision == publisherFile.revision &&
        candidate.license.toLowerCase() == publisherFile.license.toLowerCase() &&
        candidate.fileSizeBytes == publisherFile.sizeBytes &&
        candidate.licenseRepository == publisherFile.licenseRepository &&
        candidate.licenseRevision == publisherFile.licenseRevision).firstOrNull;
    if (manifest == null || publisherFile.author != manifest.repository.split('/').first ||
        publisherFile.fileName != fileName || publisherFile.sha256Hex != sha256Hex) {
      throw const AiProviderException('Model is not present in the app-pinned trust manifest.');
    }
    try {
      await channel.invokeMethod<Object?>('loadVerifiedModel', {
        'fileName': fileName,
        'sha256': sha256Hex,
        'publisherRepository': publisherFile.repository,
        'publisherAuthor': publisherFile.author,
        'publisherRevision': publisherFile.revision,
        'publisherLicense': publisherFile.license,
        'publisherSizeBytes': publisherFile.sizeBytes,
        'publisherSha256': publisherFile.sha256Hex,
        'licenseRepository': publisherFile.licenseRepository,
        'licenseRevision': publisherFile.licenseRevision,
      }).timeout(const Duration(minutes: 5));
    } on PlatformException catch (error) {
      throw AiProviderException(error.message ?? 'Verified local model could not be loaded.');
    } on MissingPluginException {
      throw const AiProviderException('Native Local AI model loader is unavailable.');
    } on TimeoutException {
      throw const AiProviderException('Native Local AI model loading timed out.');
    }
  }

  @override
  Future<AiProviderReply> complete(List<AiChatMessage> messages) async {
    if (!await canAttemptInference()) {
      throw const AiProviderException('Local AI Chat is blocked: no verified on-device model is loaded. No cloud fallback was attempted.');
    }
    if (messages.isEmpty || messages.length > 32) {
      throw const AiProviderException('Local AI conversation exceeds the safe turn limit.');
    }
    final nativeMessages = <Map<String, String>>[];
    for (final message in messages) {
      final role = message.role;
      final text = message.text ?? '';
      if ((role != 'user' && role != 'assistant' && role != 'system') || text.length > 8000) {
        throw const AiProviderException('Local AI currently accepts bounded text messages only; no cloud fallback was attempted.');
      }
      nativeMessages.add({'role': role, 'content': text});
    }
    try {
      final response = await channel.invokeMethod<Object?>('complete', {
        'messages': nativeMessages,
        'maxTokens': 96,
      }).timeout(const Duration(seconds: 75), onTimeout: () async {
        try {
          await channel.invokeMethod<Object?>('cancelInference').timeout(const Duration(seconds: 2));
        } catch (_) {
          // Native generation also has a hard deadline and checks cancellation between decode steps.
        }
        throw const AiProviderException('Local inference exceeded 75 seconds and was stopped. No cloud fallback was attempted.');
      });
      if (response is! String || response.trim().isEmpty || response.length > 12000) {
        throw const AiProviderException('Local inference returned an empty or oversized response. No cloud fallback was attempted.');
      }
      return AiProviderReply(text: response);
    } on PlatformException catch (error) {
      throw AiProviderException(error.message ?? 'Local inference failed. No cloud fallback was attempted.');
    } on MissingPluginException {
      throw const AiProviderException('Local inference bridge is unavailable. No cloud fallback was attempted.');
    } on TimeoutException {
      throw const AiProviderException('Local inference timed out. No cloud fallback was attempted.');
    }
  }
}
