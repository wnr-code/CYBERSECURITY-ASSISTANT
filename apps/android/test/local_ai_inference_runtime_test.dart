import 'package:cybersecurity_assistant/core/ai_provider_manager.dart';
import 'package:cybersecurity_assistant/core/local_ai_inference_runtime.dart';
import 'package:cybersecurity_assistant/core/local_ai_model_manifest.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/local_ai_runtime');
  const runtime = AndroidLlamaCppInferenceRuntime(channel: channel);

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('readiness requires successful local inference, while verified load permits the first Chat attempt', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
      'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
      'runtimeLoaded': true,
      'modelLoaded': false,
      'modelName': null,
      'modelSha256': null,
      'abi': 'arm64-v8a',
      'backend': 'cpu',
    });
    expect(await runtime.isReady(), isFalse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
      'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
      'runtimeLoaded': true,
      'modelLoaded': true,
      'modelName': LocalAiModelManifest.qwenQ4Km.fileName,
      'modelSha256': LocalAiModelManifest.qwenQ4Km.sha256Hex,
      'publisherMetadataVerified': true,
      'inferenceSucceeded': false,
      'offlineInferenceSucceeded': false,
      'abi': 'arm64-v8a',
      'backend': 'cpu',
    });
    expect(await runtime.isReady(), isFalse, reason: 'Loading the model alone must not mark Local AI Ready.');
    expect(await runtime.canAttemptInference(), isTrue, reason: 'The user must be able to make the first real local Chat attempt.');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
      'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
      'runtimeLoaded': true,
      'modelLoaded': true,
      'modelName': LocalAiModelManifest.qwenQ4Km.fileName,
      'modelSha256': LocalAiModelManifest.qwenQ4Km.sha256Hex,
      'publisherMetadataVerified': true,
      'inferenceSucceeded': true,
      'offlineInferenceSucceeded': false,
      'abi': 'arm64-v8a',
      'backend': 'cpu',
    });
    expect(await runtime.isReady(), isFalse, reason: 'A successful online inference alone must not mark Local AI Ready.');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
      'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
      'runtimeLoaded': true,
      'modelLoaded': true,
      'modelName': LocalAiModelManifest.qwenQ4Km.fileName,
      'modelSha256': LocalAiModelManifest.qwenQ4Km.sha256Hex,
      'publisherMetadataVerified': true,
      'inferenceSucceeded': true,
      'offlineInferenceSucceeded': true,
      'abi': 'arm64-v8a',
      'backend': 'cpu',
    });
    expect(await runtime.isReady(), isTrue);
  });

  test('runtime source or ABI mismatch fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => {
      'sourceCommit': 'unrecognized',
      'runtimeLoaded': true,
      'modelLoaded': true,
      'modelName': 'model.gguf',
      'modelSha256': List.filled(64, 'b').join(),
      'abi': 'x86_64',
      'backend': 'cpu',
    });
    expect(await runtime.isReady(), isFalse);
  });

  test('failed local inference reports no cloud fallback and never chooses another provider', () async {
    var completeInvocations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getRuntimeStatus') {
        return {
          'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
          'runtimeLoaded': true,
          'modelLoaded': true,
          'modelName': LocalAiModelManifest.qwenQ4Km.fileName,
          'modelSha256': LocalAiModelManifest.qwenQ4Km.sha256Hex,
          'publisherMetadataVerified': true,
          'inferenceSucceeded': true,
          'offlineInferenceSucceeded': true,
          'abi': 'arm64-v8a',
          'backend': 'cpu',
        };
      }
      completeInvocations++;
      throw PlatformException(code: 'local_ai_unavailable', message: 'No cloud fallback was attempted.');
    });
    await expectLater(
      runtime.complete([AiChatMessage.user('local only')]),
      throwsA(isA<AiProviderException>().having((error) => error.message, 'message', contains('No cloud fallback'))),
    );
    expect(completeInvocations, 1, reason: 'A ready local model should use native inference and never select cloud fallback.');
  });

  test('Chat is blocked without publisher metadata verification', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getRuntimeStatus') {
        return {
          'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
          'runtimeLoaded': true,
          'modelLoaded': true,
          'modelName': LocalAiModelManifest.qwenQ4Km.fileName,
          'modelSha256': LocalAiModelManifest.qwenQ4Km.sha256Hex,
          'publisherMetadataVerified': false,
          'abi': 'arm64-v8a',
          'backend': 'cpu',
        };
      }
      received = call;
      return 'local response';
    });
    await expectLater(
      runtime.complete([AiChatMessage.user('offline?')]),
      throwsA(isA<AiProviderException>().having((error) => error.message, 'message', contains('Chat is blocked'))),
    );
    expect(received, isNull);
  });
}
