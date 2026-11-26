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
          .timeout(const Duration(seconds: 3));
      return status != null &&
          status['sourceCommit'] == sourceCommit &&
          status['runtimeLoaded'] == true &&
          status['modelLoaded'] == true &&
          status['publisherMetadataVerified'] == true &&
          (!requireSuccessfulInference || (status['inferenceSucceeded'] == true && status['offlineInferenceSucceeded'] == true)) &&
          status['modelName'] == LocalAiModelManifest.qwenQ4Km.fileName &&
          status['modelSha256'] == LocalAiModelManifest.qwenQ4Km.sha256Hex &&
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
    if (fileName != 'qwen2.5-1.5b-instruct-q4_k_m.gguf' ||
        sha256Hex != '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e' ||
        publisherFile.repository != 'Qwen/Qwen2.5-1.5B-Instruct-GGUF' ||
        publisherFile.author != 'Qwen' ||
        publisherFile.revision != 'dd26da440ef0330c47919d1ecae0966d24022222' ||
        publisherFile.license.toLowerCase() != 'apache-2.0' ||
        publisherFile.fileName != fileName ||
        publisherFile.sizeBytes != 1117320736 ||
        publisherFile.sha256Hex != sha256Hex) {
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
        'maxTokens': 256,
      }).timeout(const Duration(minutes: 2));
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
