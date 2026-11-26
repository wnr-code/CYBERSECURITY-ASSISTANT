import 'package:cybersecurity_assistant/core/ai_provider_manager.dart';
import 'package:cybersecurity_assistant/core/local_ai_inference_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/local_ai_runtime');
  const runtime = AndroidLlamaCppInferenceRuntime(channel: channel);

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('readiness requires pinned runtime, verified model, arm64 ABI, and CPU backend', () async {
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
      'modelName': 'model.gguf',
      'modelSha256': List.filled(64, 'a').join(),
      'abi': 'arm64-v8a',
      'backend': 'cpu',
    });
    expect(await runtime.isReady(), isFalse, reason: 'An unverified Qwen artifact pin blocks readiness regardless of native-reported status.');
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
          'modelName': 'model.gguf',
          'modelSha256': List.filled(64, 'c').join(),
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
    expect(completeInvocations, 0, reason: 'Unverified artifact status must block the native Chat call.');
  });

  test('unverified artifact pin blocks Chat before invoking the native channel', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getRuntimeStatus') {
        return {
          'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
          'runtimeLoaded': true,
          'modelLoaded': true,
          'modelName': 'model.gguf',
          'modelSha256': List.filled(64, 'd').join(),
          'abi': 'arm64-v8a',
          'backend': 'cpu',
        };
      }
      received = call;
      return 'local response';
    });
    await expectLater(
      runtime.complete([AiChatMessage.user('offline?')]),
      throwsA(isA<AiProviderException>().having((error) => error.message, 'message', contains('Not Ready'))),
    );
    expect(received, isNull);
  });
}
