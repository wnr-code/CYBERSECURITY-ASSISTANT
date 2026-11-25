import 'dart:async';

import 'package:flutter/services.dart';

import 'ai_provider_manager.dart';

/// Flutter MethodChannel adapter for the Android arm64 llama.cpp JNI bridge.
/// It performs no networking; absent native code or a verified loaded model is
/// a hard Not Ready state, never a reason to select a cloud provider.
class AndroidLlamaCppInferenceRuntime implements LocalAiInferenceRuntime, LocalAiInferenceReadiness {
  const AndroidLlamaCppInferenceRuntime({
    this.channel = const MethodChannel('org.cybersecurityassistant/local_ai_runtime'),
  });

  static const sourceCommit = 'ea722948146befb23c9529c1ec7f59fb2f34911f';
  final MethodChannel channel;

  @override
  Future<bool> isReady() async {
    try {
      final status = await channel.invokeMapMethod<Object?, Object?>('getRuntimeStatus')
          .timeout(const Duration(seconds: 3));
      return status != null &&
          status['sourceCommit'] == sourceCommit &&
          status['runtimeLoaded'] == true &&
          status['modelLoaded'] == true &&
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

  @override
  Future<AiProviderReply> complete(List<AiChatMessage> messages) async {
    if (!await isReady()) {
      throw const AiProviderException('Local AI is Not Ready: no verified on-device model is loaded. No cloud fallback was attempted.');
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
