import 'dart:convert';
import 'dart:io';

import 'package:cybersecurity_assistant/core/diagnostics.dart';
import 'package:cybersecurity_assistant/core/package_manager.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:cybersecurity_assistant/core/tool_orchestrator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements DiagnosticQueueStore {
  Map<String, Object?> snapshot = {};
  bool failSave = false;
  @override
  Future<Map<String, Object?>> load() async => Map<String, Object?>.from(snapshot);
  @override
  Future<void> save(Map<String, Object?> data) async {
    if (failSave) throw StateError('private-path');
    snapshot = jsonDecode(jsonEncode(data)) as Map<String, Object?>;
  }
}

class _MemorySecureBackend implements SecureStorageBackend {
  final Map<String, String> values = {
    'cybersecurity_assistant.diagnostics.relay_bearer': 'test-relay-token-012345678901234567890123456789',
  };
  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _FailingPackageDownloader implements PackageDownloader {
  @override
  Future<DownloadedPackage> download(MarketPackage package, {required int maxBytes, required Duration timeout}) async {
    throw const PackageManagerException('fixture download failure');
  }
}

class _FakeUploader implements DiagnosticUploader {
  int uploads = 0;
  bool fail = false;
  DiagnosticUploadRequest? lastRequest;
  @override
  Future<void> upload(DiagnosticUploadRequest request, Uri endpoint, {required String bearerToken, required Duration timeout}) async {
    uploads++;
    lastRequest = request;
    if (fail) throw const FormatException('fixture failure');
  }
  @override
  Future<bool> testConnection(Uri endpoint, {required Duration timeout}) async => true;
}

void main() {
  group('Diagnostic sanitization', () {
    test('redacts URLs, email, credentials, IPs, and local paths', () {
      final safe = sanitizeDiagnosticText('https://host.test/p?q=x me@example.com token=abc123 192.168.1.4 /data/user/0/app/cache/a');
      expect(safe, isNot(contains('host.test')));
      expect(safe, isNot(contains('me@example.com')));
      expect(safe, isNot(contains('abc123')));
      expect(safe, isNot(contains('192.168.1.4')));
      expect(safe, isNot(contains('/data/user')));
      expect(sanitizeDiagnosticMessage("SocketException: host 'api.customer.example' refused", DiagnosticCategory.network), isNot(contains('customer.example')));
    });
    test('bounds and normalizes stack frame details', () {
      final safe = sanitizeDiagnosticStack(StackTrace.fromString('#0 /data/user/0/app/lib/main.dart:10:2\n' * 30));
      expect(safe.split('\n'), hasLength(12));
      expect(safe, isNot(contains('/data/user')));
    });
  });

  test('relay sanitization redacts common credential formats and separates local-only fields', () async {
    final safe = sanitizeDiagnosticText('Bearer abcdefghijklmnop token=secret123 github_pat_12345678901234567890');
    expect(safe, isNot(contains('abcdefghijklmnop')));
    expect(safe, isNot(contains('secret123')));
    expect(safe, isNot(contains('github_pat_')));

    final reporter = DiagnosticReporter(store: _MemoryStore());
    final report = await reporter.record(
      StateError('local error token=secret123'),
      category: DiagnosticCategory.assessment,
      reportType: DiagnosticReportType.assessmentError,
      severity: DiagnosticSeverity.high,
      component: 'assessment_manager',
      assessmentId: 'assessment-123',
      executionId: 'execution-456',
      runtimeStatus: 'failed',
      reproductionSteps: 'Run the assessment again',
    );
    final local = report.toJson();
    final outbound = report.toRelayJson();
    expect(outbound['assessmentId'], 'assessment-123');
    expect(outbound['executionId'], 'execution-456');
    expect(outbound['reproductionSteps'], 'Run the assessment again');
    expect(outbound.containsKey('fingerprint'), isFalse);
    expect(outbound.containsKey('uploadApproved'), isFalse);
    expect(outbound.containsKey('attempts'), isFalse);
    expect(outbound.containsKey('isLocalTest'), isFalse);
    expect(local.containsKey('fingerprint'), isTrue);
    reporter.dispose();
  });

  test('Flutter framework and uncaught platform async hooks persist sanitized reports', () async {
    final store = _MemoryStore();
    final reporter = DiagnosticReporter(store: store);
    final previousReporter = DiagnosticReporter.active;
    final previousFlutterHandler = FlutterError.onError;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    try {
      DiagnosticHooks.install(reporter);
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('https://private.example/token=secret'), stack: StackTrace.current));
      final platformHandler = PlatformDispatcher.instance.onError;
      expect(platformHandler, isNotNull);
      platformHandler!(Exception('uncaught async'), StackTrace.current);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reporter.reports.map((report) => report.category), containsAll([DiagnosticCategory.flutter, DiagnosticCategory.dart]));
      expect(reporter.reports.any((report) => report.message.contains('private.example') || report.message.contains('secret')), isFalse);
    } finally {
      FlutterError.onError = previousFlutterHandler;
      PlatformDispatcher.instance.onError = previousPlatformHandler;
      reporter.dispose();
      DiagnosticReporter.active = previousReporter;
    }
  });

  test('tool network and Market package failures reach diagnostic capture', () async {
    final store = _MemoryStore();
    final reporter = DiagnosticReporter(store: store);
    final previousReporter = DiagnosticReporter.active;
    DiagnosticReporter.active = reporter;
    Directory? support;
    final manager = MarketPackageManager(
      catalog: [
        MarketPackage(
          id: 'knowledge.capture', name: 'Capture fixture', description: 'Non-executable test package.',
          category: MarketCategory.knowledgePacks, version: '1.0.0', downloadSizeBytes: 100,
          officialSource: 'Test source', officialSourceUri: Uri(scheme: 'https', host: 'github.com', path: '/fixture'),
          license: 'CC0-1.0', platforms: ['Android'], architectures: ['any'], dependencies: [], runtimeRequirements: [],
          permissions: [], compatibility: PackageCompatibility.compatible, installationGuide: 'Fixture only.',
          payloadType: PackagePayloadType.jsonData, sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          downloadUri: Uri(scheme: 'https', host: 'packages.example.test', path: '/fixture.json'),
        ),
      ],
      environment: const CompatibilityEnvironment(platform: 'Android', architecture: 'arm64-v8a'),
      downloader: _FailingPackageDownloader(),
      supportDirectoryProvider: () async {
        support ??= await Directory.systemTemp.createTemp('diagnostic-market-');
        return support!;
      },
    );
    try {
      final orchestrator = ToolOrchestrator(tools: SecurityTools(hostResolver: (_) async => throw const SocketException('refused api.private.example')));
      await expectLater(orchestrator.execute(const ToolInvocation(toolId: 'dns_lookup', target: 'example.test', authorized: true)), throwsA(isA<ToolExecutionException>()));
      await manager.initialize();
      await expectLater(manager.install(manager.catalog.single, licenseAccepted: true), throwsA(isA<PackageManagerException>()));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(reporter.reports.map((report) => report.category), containsAll([DiagnosticCategory.network, DiagnosticCategory.package]));
      expect(reporter.reports.any((report) => report.message.contains('private.example')), isFalse);
    } finally {
      manager.dispose();
      reporter.dispose();
      DiagnosticReporter.active = previousReporter;
      final directory = support;
      if (directory != null && await directory.exists()) await directory.delete(recursive: true);
    }
  });

  group('Diagnostic reporter', () {
    late _MemoryStore store;
    late _FakeUploader uploader;
    late DateTime now;
    late DiagnosticReporter reporter;
    late _MemorySecureBackend secureBackend;
    late DiagnosticRelaySecretStore secretStore;
    setUp(() {
      store = _MemoryStore();
      uploader = _FakeUploader();
      now = DateTime.utc(2026, 11, 23);
      secureBackend = _MemorySecureBackend();
      secretStore = DiagnosticRelaySecretStore(backend: secureBackend);
      reporter = DiagnosticReporter(store: store, uploader: uploader, relaySecretStore: secretStore, clock: () => now, wifiAvailable: () async => true);
    });
    tearDown(() => reporter.dispose());

    test('queues locally without a relay and requires explicit consent before automatic upload', () async {
      final row = await reporter.record(StateError('private-path https://internal.test?token=secret'), category: DiagnosticCategory.startup);
      expect(row.status, DiagnosticStatus.waitingForReview);
      expect(reporter.pendingCount, 1);
      expect(uploader.uploads, 0);
      await expectLater(reporter.configure(const DiagnosticSettings(autoReportingEnabled: true)), throwsStateError);
      expect(uploader.uploads, 0);
      expect(store.snapshot['reports'], isA<List>());
    });

    test('relay credentials stay in secure storage and cannot be exported', () async {
      await reporter.configure(const DiagnosticSettings(backendEndpoint: 'https://relay.example.test/diagnostics'));
      await reporter.clearRelayCredential();
      expect(reporter.hasRelay, isFalse);
      await reporter.saveRelayCredential('another-test-relay-token-01234567890123456789');
      expect(reporter.hasRelay, isTrue);
      expect(secureBackend.values['cybersecurity_assistant.diagnostics.relay_bearer'], 'another-test-relay-token-01234567890123456789');
      expect(reporter.exportReport(), isNot(contains('another-test-relay-token')));
      await expectLater(reporter.saveRelayCredential('too-short'), throwsFormatException);
    });

    test('local self-test persists and can never be uploaded, even when auto-reporting is enabled', () async {
      await reporter.configure(const DiagnosticSettings(
        consentGranted: true,
        autoReportingEnabled: true,
        reviewBeforeUpload: false,
        backendEndpoint: 'https://relay.example.test/diagnostics',
      ));
      final row = await reporter.recordLocalTestReport();
      expect(row.isLocalTest, isTrue);
      expect(row.message, contains('bukan error aplikasi'));
      await reporter.approveAndUpload(row.id);
      await reporter.retryPending();
      expect(uploader.uploads, 0);
      final restored = DiagnosticReporter(store: store, uploader: uploader, relaySecretStore: secretStore);
      await restored.initialize();
      expect(restored.reports.single.isLocalTest, isTrue);
      await restored.retryPending();
      expect(uploader.uploads, 0);
      restored.dispose();
    });

    test('Local AI reports stay local for individual review even when automatic reporting is enabled', () async {
      await reporter.configure(const DiagnosticSettings(
        consentGranted: true,
        autoReportingEnabled: true,
        reviewBeforeUpload: false,
        backendEndpoint: 'https://relay.example.test/diagnostics',
      ));
      final row = await reporter.record(
        StateError('Local AI diagnostic'),
        category: DiagnosticCategory.native,
        message: 'Local AI status: BLOCKED; path=/data/user/0/private; token=secret123',
        component: 'local_ai_device_diagnostic',
        requireManualReview: true,
      );
      await reporter.configure(const DiagnosticSettings(
        consentGranted: true,
        autoReportingEnabled: true,
        reviewBeforeUpload: false,
        backendEndpoint: 'https://relay.example.test/diagnostics',
      ));
      await reporter.retryPending();
      expect(row.status, DiagnosticStatus.waitingForReview);
      expect(row.uploadApproved, isFalse);
      expect(row.message, isNot(contains('/data/user')));
      expect(row.message, isNot(contains('secret123')));
      expect(uploader.uploads, 0);
      expect(store.snapshot['reports'], isA<List>());
    });

    test('automatic reporting OFF keeps consented reports local', () async {
      await reporter.configure(const DiagnosticSettings(consentGranted: true, autoReportingEnabled: false, reviewBeforeUpload: false, backendEndpoint: 'https://relay.example.test/diagnostics'));
      await reporter.record(Exception('local only'), category: DiagnosticCategory.network);
      await reporter.retryPending();
      expect(uploader.uploads, 0);
      expect(reporter.pendingCount, 1);
    });

    test('persists the offline queue across reporter reinitialization', () async {
      await reporter.record(StateError('local record'), category: DiagnosticCategory.startup);
      final restored = DiagnosticReporter(store: store, uploader: uploader, relaySecretStore: secretStore);
      await restored.initialize();
      expect(restored.pendingCount, 1);
      expect(restored.reports.single.message, contains('local record'));
      restored.dispose();
    });

    test('deduplicates identical fingerprints and persists occurrences', () async {
      final one = await reporter.record(ArgumentError('first'), stackTrace: StackTrace.fromString('#0 package:app/a.dart:1:2'), category: DiagnosticCategory.dart);
      now = now.add(const Duration(minutes: 2));
      final two = await reporter.record(ArgumentError('second'), stackTrace: StackTrace.fromString('#0 package:app/a.dart:8:9'), category: DiagnosticCategory.dart);
      expect(one.id, two.id);
      expect(two.occurrences, 2);
      expect(reporter.reports, hasLength(1));
    });

    test('manual approved upload includes required labels and records success timestamp', () async {
      await reporter.configure(const DiagnosticSettings(consentGranted: true, autoReportingEnabled: true, reviewBeforeUpload: true, backendEndpoint: 'https://relay.example.test/diagnostics'));
      final row = await reporter.record(Exception('safe error'), category: DiagnosticCategory.network);
      await reporter.approveAndUpload(row.id);
      expect(uploader.uploads, 1);
      expect(uploader.lastRequest!.toJson()['labels'], diagnosticLabels);
      expect(reporter.reports.single.status, DiagnosticStatus.sent);
      expect(reporter.lastSuccessfulUpload, now);
    });

    test('failed uploads back off, preserve retry time, and succeed after the delay', () async {
      uploader.fail = true;
      await reporter.configure(const DiagnosticSettings(consentGranted: true, autoReportingEnabled: true, reviewBeforeUpload: true, backendEndpoint: 'https://relay.example.test/diagnostics'));
      final row = await reporter.record(Exception('bad'), category: DiagnosticCategory.dart);
      await reporter.approveAndUpload(row.id);
      final failed = reporter.reports.single;
      expect(failed.status, DiagnosticStatus.failed);
      expect(failed.attempts, 1);
      expect(failed.lastUploadError, 'FormatException');
      expect(failed.nextAttemptAt, now.add(const Duration(minutes: 1)));
      uploader.fail = false;
      await reporter.configure(reporter.settings.copyWith(reviewBeforeUpload: false));
      expect(reporter.reports.single.nextAttemptAt, failed.nextAttemptAt);
      now = now.add(const Duration(minutes: 1));
      await reporter.retryPending();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(uploader.uploads, 2);
      expect(reporter.reports.single.status, DiagnosticStatus.sent);
      expect(reporter.reports.single.attempts, 2);
    });

    test('does not send after the retry attempt limit', () async {
      final limitedUploader = _FakeUploader()..fail = true;
      final limited = DiagnosticReporter(store: store, uploader: limitedUploader, relaySecretStore: secretStore, maxAttempts: 1);
      await limited.configure(const DiagnosticSettings(consentGranted: true, autoReportingEnabled: true, reviewBeforeUpload: true, backendEndpoint: 'https://relay.example.test/diagnostics'));
      final row = await limited.record(Exception('limited'), category: DiagnosticCategory.dart);
      await limited.approveAndUpload(row.id);
      await limited.approveAndUpload(row.id);
      expect(limitedUploader.uploads, 1);
      expect(limited.reports.single.attempts, 1);
      limited.dispose();
    });

    test('Wi-Fi-only mode waits when offline, delete removes pending reports, and export omits relay URL', () async {
      var wifi = false;
      final local = DiagnosticReporter(store: store, uploader: uploader, relaySecretStore: secretStore, wifiAvailable: () async => wifi);
      await local.configure(const DiagnosticSettings(consentGranted: true, autoReportingEnabled: true, wifiOnly: true, reviewBeforeUpload: false, backendEndpoint: 'https://relay.example.test/path'));
      await local.record(Exception('network'), category: DiagnosticCategory.network);
      await local.retryPending();
      expect(uploader.uploads, 0);
      expect(local.exportReport(), isNot(contains('relay.example.test')));
      await local.deletePendingReports();
      expect(local.pendingCount, 0);
      local.dispose();
    });

    test('rejects non-HTTPS or secret-bearing relay URLs and reports storage errors without leaking paths', () async {
      await expectLater(reporter.configure(const DiagnosticSettings(backendEndpoint: 'http://relay.example.test')), throwsFormatException);
      await expectLater(reporter.configure(const DiagnosticSettings(backendEndpoint: 'https://relay.example.test/?token=secret')), throwsFormatException);
      store.failSave = true;
      await reporter.record(Exception('failure'), category: DiagnosticCategory.database);
      expect(reporter.reports.single.category, DiagnosticCategory.database);
      expect(reporter.storageWarning, 'StateError');
    });

    test('imports and deletes a bounded native crash breadcrumb after sanitizing it', () async {
      final file = File('${Directory.systemTemp.path}/diagnostic-native-${DateTime.now().microsecondsSinceEpoch}.txt');
      await file.writeAsString('NativeException /data/user/0/app/private https://private.example/path');
      final imported = await consumeNativeCrashFile(reporter, file);
      expect(imported, isTrue);
      expect(await file.exists(), isFalse);
      expect(reporter.reports.single.category, DiagnosticCategory.native);
      expect(reporter.reports.single.message, isNot(contains('/data/user')));
      expect(reporter.reports.single.message, isNot(contains('private.example')));
    });
  });
}
