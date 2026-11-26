import 'package:cybersecurity_assistant/core/local_ai_model_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';

const _testDigest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  LocalAiModelCompatibilityMetadata model({
    String? format = 'litertlm-bundle',
    String? architecture = 'gemma4',
    String? tokenizer = 'gemma4-chat-v1',
    String? minimumRuntimeVersion = '0.19.0',
    int? peakMemoryBytes = 2 * 1024 * 1024 * 1024,
    int? installStorageBytes = 3 * 1024 * 1024 * 1024,
    String? sha256 = _testDigest,
    bool metadataVerified = true,
    bool digestVerified = true,
  }) => LocalAiModelCompatibilityMetadata(
        bundleFormat: format,
        architecture: architecture,
        tokenizer: tokenizer,
        minimumRuntimeVersion: minimumRuntimeVersion,
        peakMemoryBytes: peakMemoryBytes,
        installStorageBytes: installStorageBytes,
        sha256: sha256,
        publisherMetadataVerified: metadataVerified,
        artifactDigestVerified: digestVerified,
      );

  const runtime = LocalAiRuntimeCompatibilityProfile(
    available: true,
    version: '0.19.1',
    bundleFormats: {'litertlm-bundle'},
    architectures: {'gemma4'},
    tokenizers: {'gemma4-chat-v1'},
    supportedAbis: {'arm64-v8a'},
  );

  const device = LocalAiDeviceCompatibilityProfile(
    supportedAbis: ['arm64-v8a'],
    availableRamBytes: 8 * 1024 * 1024 * 1024,
    memoryHeadroomBytes: 2 * 1024 * 1024 * 1024,
    availableStorageBytes: 8 * 1024 * 1024 * 1024,
  );

  test('reports compatible only when verified metadata and every capability match', () {
    final report = LocalAiModelCompatibilityChecker.evaluate(model: model(), runtime: runtime, device: device);
    expect(report.state, LocalAiCompatibilityState.compatible);
    expect(report.issues, isEmpty);
  });

  test('unknown model metadata fails closed instead of inferring support from device RAM or ABI', () {
    final report = LocalAiModelCompatibilityChecker.evaluate(
      model: model(format: null, architecture: null, tokenizer: null, minimumRuntimeVersion: null),
      runtime: runtime,
      device: device,
    );
    expect(report.state, LocalAiCompatibilityState.unknown);
    expect(report.issues, contains(LocalAiCompatibilityIssue.bundleFormatUnknown));
    expect(report.issues, contains(LocalAiCompatibilityIssue.architectureUnknown));
    expect(report.issues, contains(LocalAiCompatibilityIssue.tokenizerUnknown));
    expect(report.issues, contains(LocalAiCompatibilityIssue.runtimeVersionUnknown));
  });

  test('rejects mismatched architecture, tokenizer, and insufficient memory or storage', () {
    final report = LocalAiModelCompatibilityChecker.evaluate(
      model: model(format: 'unsupported-container', architecture: 'unknown-family', tokenizer: 'unsupported-tokenizer',
          peakMemoryBytes: 7 * 1024 * 1024 * 1024, installStorageBytes: 9 * 1024 * 1024 * 1024),
      runtime: runtime,
      device: device,
    );
    expect(report.state, LocalAiCompatibilityState.incompatible);
    expect(report.issues, contains(LocalAiCompatibilityIssue.bundleFormatUnsupported));
    expect(report.issues, contains(LocalAiCompatibilityIssue.architectureUnsupported));
    expect(report.issues, contains(LocalAiCompatibilityIssue.tokenizerUnsupported));
    expect(report.issues, contains(LocalAiCompatibilityIssue.insufficientMemory));
    expect(report.issues, contains(LocalAiCompatibilityIssue.insufficientStorage));
  });

  test('rejects incompatible ABI and unsupported runtime version', () {
    final incompatibleRuntime = LocalAiRuntimeCompatibilityProfile(
      available: true,
      version: '0.18.0',
      bundleFormats: runtime.bundleFormats,
      architectures: runtime.architectures,
      tokenizers: runtime.tokenizers,
      supportedAbis: const {'x86_64'},
    );
    final report = LocalAiModelCompatibilityChecker.evaluate(model: model(), runtime: incompatibleRuntime, device: device);
    expect(report.state, LocalAiCompatibilityState.incompatible);
    expect(report.issues, contains(LocalAiCompatibilityIssue.runtimeVersionUnsupported));
    expect(report.issues, contains(LocalAiCompatibilityIssue.noCommonAbi));
  });

  test('unverified publisher metadata or digest never reports compatible', () {
    final report = LocalAiModelCompatibilityChecker.evaluate(
      model: model(metadataVerified: false, digestVerified: false),
      runtime: runtime,
      device: device,
    );
    expect(report.state, LocalAiCompatibilityState.unknown);
    expect(report.isCompatible, isFalse);
  });
}
