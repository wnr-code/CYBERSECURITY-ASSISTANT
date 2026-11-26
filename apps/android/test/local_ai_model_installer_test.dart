import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cybersecurity_assistant/core/local_ai_model_installer.dart';
import 'package:cybersecurity_assistant/core/local_ai_model_source.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeArtifactSource implements LocalAiArtifactSource {
  _FakeArtifactSource(this.manifest, this.bytes, {this.publisherOverride, this.interruptFirstRangeOnce = false});

  final LocalAiModelManifest manifest;
  final List<int> bytes;
  final LocalAiPublisherFile? publisherOverride;
  final bool interruptFirstRangeOnce;
  bool _didInterruptFirstRange = false;
  int downloadCalls = 0;
  final requestedRanges = <String>[];

  @override
  Future<LocalAiPublisherFile> fetchPublisherMetadata(LocalAiModelManifest requested) async => publisherOverride ?? LocalAiPublisherFile(
        repository: manifest.repository,
        author: manifest.repository.split('/').first,
        revision: manifest.revision,
        license: manifest.license,
        fileName: manifest.fileName,
        sizeBytes: manifest.fileSizeBytes,
        sha256Hex: manifest.sha256Hex,
      );

  @override
  Future<LocalAiDownloadResponse> openPinnedDownload(
    LocalAiModelManifest requested, {
    required int rangeStart,
    required int rangeEnd,
  }) async {
    downloadCalls++;
    requestedRanges.add('$rangeStart-$rangeEnd');
    var rangeBytes = bytes.sublist(rangeStart, rangeEnd + 1);
    if (interruptFirstRangeOnce && !_didInterruptFirstRange && rangeStart == 0) {
      _didInterruptFirstRange = true;
      rangeBytes = rangeBytes.sublist(0, rangeBytes.length ~/ 2);
    }
    final split = rangeBytes.length ~/ 2;
    return LocalAiDownloadResponse(
      statusCode: 206,
      contentLength: rangeEnd - rangeStart + 1,
      contentRange: 'bytes $rangeStart-$rangeEnd/${requested.fileSizeBytes}',
      body: Stream<List<int>>.fromIterable([rangeBytes.sublist(0, split), rangeBytes.sublist(split)]),
      dispose: () async {},
    );
  }
}

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
      revision: List.filled(40, 'a').join(),
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
    expect(LocalAiModelManifest.qwenArtifactIndependentlyVerified, isFalse);
    expect(qwen.repository, 'Qwen/Qwen2.5-1.5B-Instruct-GGUF');
    expect(qwen.revision, '91cad51170dc346986eccefdc2dd33a9da36ead9');
    expect(qwen.fileName, 'qwen2.5-1.5b-instruct-q4_k_m.gguf');
    expect(qwen.license, 'Apache-2.0');
    expect(qwen.fileSizeBytes, 1117320736);
    expect(qwen.sha256Hex, '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e');
    expect(qwen.downloadUrl, contains('/resolve/${qwen.revision}/'));
  });

  test('production file-picker import stays disabled; verified on-device download is the only production path', () async {
    var pickerCalled = false;
    final installer = LocalAiModelInstaller(
      pickFile: () async { pickerCalled = true; return null; },
      supportDirectory: () async => supportDirectory,
    );
    await expectLater(
      installer.chooseVerifyAndLoad(),
      throwsA(isA<LocalAiModelInstallException>().having((error) => error.message, 'message', contains('File-picker model import is disabled'))),
    );
    expect(pickerCalled, isFalse);
    expect(await supportDirectory.list().toList(), isEmpty);
  });

  test('official Hugging Face metadata parser checks publisher, revision, license, file size, and LFS SHA', () {
    final valid = <String, Object?>{
      'id': manifest.repository,
      'author': 'test',
      'sha': manifest.revision,
      'cardData': {'license': 'test-only'},
      'siblings': [
        {
          'rfilename': manifest.fileName,
          'size': manifest.fileSizeBytes,
          'lfs': {'size': manifest.fileSizeBytes, 'sha256': modelDigest},
        },
      ],
    };
    final parsed = HuggingFaceLocalAiArtifactSource.parsePublisherMetadataJson(jsonEncode(valid), manifest);
    expect(parsed.repository, manifest.repository);
    expect(parsed.author, 'test');
    expect(parsed.revision, manifest.revision);
    expect(parsed.license, manifest.license);
    expect(parsed.sizeBytes, manifest.fileSizeBytes);
    expect(parsed.sha256Hex, modelDigest);

    final wrongRevision = Map<String, Object?>.from(valid)..['sha'] = List.filled(40, 'b').join();
    expect(
      () => HuggingFaceLocalAiArtifactSource.parsePublisherMetadataJson(jsonEncode(wrongRevision), manifest),
      throwsA(isA<LocalAiModelInstallException>()),
    );

    final missingLicense = Map<String, dynamic>.from(jsonDecode(jsonEncode(valid)) as Map<String, dynamic>)
      ..remove('cardData');
    expect(
      () => HuggingFaceLocalAiArtifactSource.parsePublisherMetadataJson(jsonEncode(missingLicense), manifest),
      throwsA(isA<LocalAiModelInstallException>()),
      reason: 'License verification must fail closed when the Hub response omits full model-card metadata.',
    );

    final legacyOid = Map<String, dynamic>.from(jsonDecode(jsonEncode(valid)) as Map<String, dynamic>);
    final legacySibling = (legacyOid['siblings'] as List).single as Map<String, dynamic>;
    legacySibling['lfs'] = {'size': manifest.fileSizeBytes, 'oid': 'sha256:$modelDigest'};
    expect(
      HuggingFaceLocalAiArtifactSource.parsePublisherMetadataJson(jsonEncode(legacyOid), manifest).sha256Hex,
      modelDigest,
    );

    final conflictingSha = Map<String, dynamic>.from(jsonDecode(jsonEncode(valid)) as Map<String, dynamic>);
    final conflictingSibling = (conflictingSha['siblings'] as List).single as Map<String, dynamic>;
    conflictingSibling['lfs']['oid'] = 'sha256:${List.filled(64, '0').join()}';
    expect(
      () => HuggingFaceLocalAiArtifactSource.parsePublisherMetadataJson(jsonEncode(conflictingSha), manifest),
      throwsA(isA<LocalAiModelInstallException>()),
    );
  });

  test('on-device download verifies publisher pin and complete file before native loading with progress', () async {
    final bytes = utf8.encode(modelBytes);
    final source = _FakeArtifactSource(manifest, bytes);
    final stages = <LocalAiInstallPhase>[];
    var loaded = false;
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      testOnlyAllowUnverifiedManifest: true,
      supportDirectory: () async => supportDirectory,
      artifactSource: source,
      availableStorageBytes: () async => manifest.fileSizeBytes + 128 * 1024 * 1024,
      loadModel: (name, digest, publisher) async {
        expect(name, manifest.fileName);
        expect(digest, modelDigest);
        expect(publisher.sha256Hex, modelDigest);
        loaded = true;
      },
    );

    final result = await installer.downloadVerifyAndLoad(onProgress: (progress) => stages.add(progress.phase));
    final installed = File('${supportDirectory.path}/local_ai/models/test.gguf');
    expect(await installed.readAsBytes(), bytes);
    expect(result.sha256Hex, modelDigest);
    expect(loaded, isTrue);
    expect(source.downloadCalls, 1);
    expect(stages, containsAll([
      LocalAiInstallPhase.checkingPublisher,
      LocalAiInstallPhase.downloading,
      LocalAiInstallPhase.verifying,
      LocalAiInstallPhase.loading,
      LocalAiInstallPhase.complete,
    ]));
  });

  test('resumes a partial model download from its exact saved byte offset', () async {
    final bytes = utf8.encode(modelBytes);
    final modelDirectory = Directory('${supportDirectory.path}/local_ai/models')..createSync(recursive: true);
    final partial = File('${modelDirectory.path}/${manifest.fileName}.part');
    final checkpoint = bytes.length ~/ 2;
    await partial.writeAsBytes(bytes.sublist(0, checkpoint), flush: true);
    final source = _FakeArtifactSource(manifest, bytes);
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      testOnlyAllowUnverifiedManifest: true,
      supportDirectory: () async => supportDirectory,
      artifactSource: source,
      availableStorageBytes: () async => manifest.fileSizeBytes + 128 * 1024 * 1024,
      loadModel: (_, __, ___) async {},
    );

    final result = await installer.downloadVerifyAndLoad();
    expect(source.requestedRanges, ['${checkpoint}-${bytes.length - 1}']);
    expect(await File('${modelDirectory.path}/${manifest.fileName}').readAsBytes(), bytes);
    expect(result.sha256Hex, modelDigest);
    expect(await partial.exists(), isFalse);
  });

  test('retries a dropped range from the last byte received instead of restarting', () async {
    final bytes = utf8.encode(modelBytes);
    final source = _FakeArtifactSource(manifest, bytes, interruptFirstRangeOnce: true);
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      testOnlyAllowUnverifiedManifest: true,
      supportDirectory: () async => supportDirectory,
      artifactSource: source,
      availableStorageBytes: () async => manifest.fileSizeBytes + 128 * 1024 * 1024,
      loadModel: (_, __, ___) async {},
    );

    final result = await installer.downloadVerifyAndLoad();
    final checkpoint = bytes.length ~/ 2;
    expect(source.requestedRanges, ['0-${bytes.length - 1}', '$checkpoint-${bytes.length - 1}']);
    expect(result.sha256Hex, modelDigest);
    expect(await File('${supportDirectory.path}/local_ai/models/${manifest.fileName}').readAsBytes(), bytes);
  });

  test('storage failure preserves an existing file until a replacement passes verification', () async {
    final directory = Directory('${supportDirectory.path}/local_ai/models')..createSync(recursive: true);
    final existing = File('${directory.path}/${manifest.fileName}')..writeAsStringSync('previous bytes');
    final source = _FakeArtifactSource(manifest, utf8.encode(modelBytes));
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      testOnlyAllowUnverifiedManifest: true,
      supportDirectory: () async => supportDirectory,
      artifactSource: source,
      availableStorageBytes: () async => null,
      loadModel: (_, __, ___) async => fail('Native loader must not run when storage is unknown.'),
    );
    await expectLater(installer.downloadVerifyAndLoad(), throwsA(isA<LocalAiModelInstallException>()));
    expect(await existing.readAsString(), 'previous bytes');
    expect(source.downloadCalls, 0);
  });

  test('publisher mismatch and actual GGUF hash mismatch fail before native loading', () async {
    final bytes = utf8.encode(modelBytes);
    final wrongPublisher = _FakeArtifactSource(manifest, bytes, publisherOverride: LocalAiPublisherFile(
      repository: manifest.repository,
      author: 'attacker',
      revision: manifest.revision,
      license: manifest.license,
      fileName: manifest.fileName,
      sizeBytes: manifest.fileSizeBytes,
      sha256Hex: modelDigest,
    ));
    final first = LocalAiModelInstaller(
      manifest: manifest,
      testOnlyAllowUnverifiedManifest: true,
      supportDirectory: () async => supportDirectory,
      artifactSource: wrongPublisher,
      availableStorageBytes: () async => manifest.fileSizeBytes + 128 * 1024 * 1024,
      loadModel: (_, __, ___) async => fail('Native loader must not run.'),
    );
    await expectLater(first.downloadVerifyAndLoad(), throwsA(isA<LocalAiModelInstallException>()));
    expect(wrongPublisher.downloadCalls, 0);
    expect(await supportDirectory.list().toList(), isEmpty);

    final tamperedBytes = List<int>.from(bytes);
    tamperedBytes[0] ^= 1;
    final tamperedSource = _FakeArtifactSource(manifest, tamperedBytes);
    final second = LocalAiModelInstaller(
      manifest: manifest,
      testOnlyAllowUnverifiedManifest: true,
      supportDirectory: () async => supportDirectory,
      artifactSource: tamperedSource,
      availableStorageBytes: () async => manifest.fileSizeBytes + 128 * 1024 * 1024,
      loadModel: (_, __, ___) async => fail('Native loader must not run for a wrong file hash.'),
    );
    await expectLater(second.downloadVerifyAndLoad(), throwsA(isA<LocalAiModelInstallException>().having((error) => error.message, 'message', contains('SHA-256'))));
    expect(await Directory('${supportDirectory.path}/local_ai/models').list().toList(), isEmpty);
  });

  test('copies only exact-size, exact-SHA bytes before invoking native loader', () async {
    var loadedName = '';
    var loadedDigest = '';
    final installer = LocalAiModelInstaller(
      manifest: manifest,
      supportDirectory: () async => supportDirectory,
      testOnlyAllowUnverifiedManifest: true,
      loadModel: (name, digest, _) async { loadedName = name; loadedDigest = digest; },
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
      testOnlyAllowUnverifiedManifest: true,
      loadModel: (_, __, ___) async { loaderCalled = true; },
    );

    await expectLater(
      installer.verifyAndLoadStream(fileName: manifest.fileName, source: Stream<List<int>>.value(utf8.encode('tampered content'))),
      throwsA(isA<LocalAiModelInstallException>().having((error) => error.message, 'message', contains('Test-file verification failed'))),
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
      testOnlyAllowUnverifiedManifest: true,
      loadModel: (_, __, ___) async {
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
