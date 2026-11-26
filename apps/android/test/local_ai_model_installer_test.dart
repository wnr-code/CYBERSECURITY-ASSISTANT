import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cybersecurity_assistant/core/local_ai_model_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory supportDirectory;
  late LocalAiModelManifest manifest;
  const modelBytes = 'small test GGUF bytes';
  late String modelDigest;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp('local-ai-model-installer-test-');
    modelDigest = sha256.convert(utf8.encode(modelBytes)).toString();
    manifest = LocalAiModelManifest(
      repository: 'test/pinned-model',
      revision: 'test-revision',
      fileName: 'test.gguf',
      license: 'test-only',
      fileSizeBytes: utf8.encode(modelBytes).length,
      sha256Hex: modelDigest,
      downloadUrl: 'https://example.invalid/pinned/test.gguf',
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) await supportDirectory.delete(recursive: true);
  });

  test('Qwen production manifest pins the requested immutable model metadata', () {
    const qwen = LocalAiModelManifest.qwenQ4Km;
    expect(qwen.repository, 'Qwen/Qwen2.5-1.5B-Instruct-GGUF');
    expect(qwen.revision, 'dd26da440ef0330c47919d1ecae0966d24022222');
    expect(qwen.fileName, 'qwen2.5-1.5b-instruct-q4_k_m.gguf');
    expect(qwen.license, 'Apache-2.0');
    expect(qwen.fileSizeBytes, 1117320736);
    expect(qwen.sha256Hex, '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e');
    expect(qwen.downloadUrl, contains('/resolve/${qwen.revision}/'));
  });

  test('unverified production Qwen pin blocks selection, storage, and native loading', () async {
    var pickerCalled = false;
    final installer = LocalAiModelInstaller(
      pickFile: () async { pickerCalled = true; return null; },
      supportDirectory: () async => supportDirectory,
    );
    await expectLater(
      installer.chooseVerifyAndLoad(),
      throwsA(isA<LocalAiModelInstallException>().having((error) => error.message, 'message', contains('not been independently verified'))),
    );
    expect(pickerCalled, isFalse);
    expect(await supportDirectory.list().toList(), isEmpty);
    expect(LocalAiModelManifest.qwenArtifactIndependentlyVerified, isFalse);
  });

  test('copies only exact-size, exact-SHA bytes before invoking native loader', () async {
    var loadedName = '';
    var loadedDigest = '';
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      supportDirectory: () async => supportDirectory,
      allowUnverifiedManifestForTests: true,
      loadModel: (name, digest) async { loadedName = name; loadedDigest = digest; },
    );

    final result = await installer.verifyAndLoadStream(
      fileName: manifest.fileName,
      source: Stream<List<int>>.value(utf8.encode(modelBytes)),
    );

    final installed = File('${supportDirectory.path}/local_ai/models/test.gguf');
    expect(await installed.readAsString(), modelBytes);
    expect(result.sizeBytes, manifest.fileSizeBytes);
    expect(result.sha256Hex, modelDigest);
    expect(loadedName, manifest.fileName);
    expect(loadedDigest, modelDigest);
  });

  test('deletes mismatched content and never invokes native loader', () async {
    var loaderCalled = false;
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      supportDirectory: () async => supportDirectory,
      allowUnverifiedManifestForTests: true,
      loadModel: (_, __) async { loaderCalled = true; },
    );

    await expectLater(
      installer.verifyAndLoadStream(fileName: manifest.fileName, source: Stream<List<int>>.value(utf8.encode('tampered content'))),
      throwsA(isA<LocalAiModelInstallException>().having((error) => error.message, 'message', contains('Model verification failed'))),
    );

    final modelDirectory = Directory('${supportDirectory.path}/local_ai/models');
    expect(loaderCalled, isFalse);
    expect(await modelDirectory.exists(), isTrue);
    expect(await modelDirectory.list().toList(), isEmpty);
  });

  test('rejects an unexpected filename before touching model storage', () async {
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      supportDirectory: () async => supportDirectory,
      allowUnverifiedManifestForTests: true,
      loadModel: (_, __) async {
        fail('Loader must not run for a filename mismatch.');
      },
    );

    await expectLater(
      installer.verifyAndLoadStream(fileName: 'other.gguf', source: Stream<List<int>>.value(utf8.encode(modelBytes))),
      throwsA(isA<LocalAiModelInstallException>()),
    );
    expect(await supportDirectory.list().toList(), isEmpty);
  });
}
