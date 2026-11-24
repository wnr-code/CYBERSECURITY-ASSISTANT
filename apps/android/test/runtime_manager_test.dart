import 'dart:async';
import 'dart:io';

import 'package:cybersecurity_assistant/core/policy_engine.dart';

import 'package:cybersecurity_assistant/core/runtime_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements RuntimeStateStore {
  Map<String, Object?> value = {};
  @override
  Future<Map<String, Object?>> load() async => Map<String, Object?>.from(value);
  @override
  Future<void> save(Map<String, Object?> snapshot) async {
    value = Map<String, Object?>.from(snapshot);
  }
}

class _Adapter implements RuntimeAdapter {
  _Adapter();
  bool healthy = true;
  int installs = 0;
  int initializes = 0;
  int stops = 0;
  int updates = 0;
  int removals = 0;
  @override
  RuntimeDescriptor get descriptor => const RuntimeDescriptor(
        id: 'runtime.fixture', name: 'Fixture Runtime', version: '1.0.0', license: 'MIT',
        supportedAbis: ['arm64-v8a'], dependencies: [], requiredCapabilities: {RuntimeCapability.filesystemRead},
        sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
  @override
  Future<void> install(Directory directory) async { installs++; await File('${directory.path}/metadata').writeAsString('installed'); }
  @override
  Future<void> initialize(Directory directory) async { initializes++; }
  @override
  Future<void> stop() async { stops++; }
  @override
  Future<void> update(Directory directory, String version) async { updates++; }
  @override
  Future<void> uninstall(Directory directory) async { removals++; }
  @override
  Future<bool> healthCheck() async => healthy;
}

class _ExecutionAdapter extends _Adapter implements RuntimeExecutionAdapter {
  _ExecutionAdapter({this.delay = Duration.zero, this.output = const {'result': 'ok'}, this.maxExecution = const Duration(milliseconds: 200), this.maxInputBytes = 128});
  final Duration delay;
  final Map<String, Object?> output;
  final Duration maxExecution;
  final int maxInputBytes;
  int executions = 0;

  @override
  RuntimeDescriptor get descriptor => RuntimeDescriptor(
        id: 'runtime.exec', name: 'Execution Fixture', version: '1.0.0', license: 'MIT',
        supportedPlatforms: const ['Android'], supportedAbis: const ['arm64-v8a'],
        dependencies: const [], requiredCapabilities: const {RuntimeCapability.network},
        supportedToolIds: const ['dns_lookup'], minAndroidApi: 29,
        sha256: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        resourceLimit: RuntimeResourceLimit(maxExecution: maxExecution, maxInputBytes: maxInputBytes, maxOutputBytes: 128),
      );

  @override
  Future<Map<String, Object?>> executeTool(RuntimeToolRequest request) async {
    executions++;
    if (delay > Duration.zero) {
      await Future.any<void>([
        Future<void>.delayed(delay),
        request.cancellationToken.whenCancelled.then((_) => throw const RuntimeExecutionCancelled()),
      ]);
    }
    request.cancellationToken.throwIfCancelled();
    return output;
  }
}

class _DependentAdapter extends _Adapter {
  @override
  RuntimeDescriptor get descriptor => const RuntimeDescriptor(
        id: 'runtime.dependent', name: 'Dependent Runtime', version: '1.0.0', license: 'MIT',
        supportedAbis: ['arm64-v8a'], dependencies: ['runtime.absent'], requiredCapabilities: {RuntimeCapability.filesystemRead},
        sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
}

void main() {
  late Directory root;
  late _Store store;
  late _Adapter adapter;
  late RuntimeManager manager;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('runtime-manager-');
    store = _Store();
    adapter = _Adapter();
    manager = RuntimeManager(environment: const RuntimeEnvironment(platform: 'Android', abi: 'arm64-v8a'), store: store,
        adapters: [adapter], supportDirectoryProvider: () async => root);
  });
  tearDown(() async { manager.dispose(); if (await root.exists()) await root.delete(recursive: true); });

  group('runtime execution', () {
    const environment = RuntimeEnvironment(
      platform: 'Android', abi: 'arm64-v8a', deviceAbis: ['arm64-v8a', 'armeabi-v7a'], androidApiLevel: 35,
      availableCapabilities: {RuntimeCapability.network, RuntimeCapability.filesystemRead},
    );

    test('discovers adapter only after installation; authorizes and audits execution', () async {
      final executionAdapter = _ExecutionAdapter();
      final executionManager = RuntimeManager(environment: environment, store: _Store(), adapters: [executionAdapter], supportDirectoryProvider: () async => root);
      expect((await executionManager.discover()).single.status, RuntimeDiscoveryStatus.notInstalled);
      await executionManager.install(executionAdapter.descriptor.id, userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.network});
      expect((await executionManager.discover()).single.status, RuntimeDiscoveryStatus.available);
      final result = await executionManager.executeTool(runtimeId: executionAdapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'example.com'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true);
      expect(result.output, {'result': 'ok'});
      expect(executionAdapter.executions, 1);
      expect(executionManager.auditEvents.map((event) => event['action']), containsAll(['tool-start', 'tool-complete']));
      executionManager.dispose();
    });

    test('rejects missing policy consent and unregistered capabilities before execution', () async {
      final executionAdapter = _ExecutionAdapter();
      final executionManager = RuntimeManager(environment: environment, store: _Store(), adapters: [executionAdapter], supportDirectoryProvider: () async => root);
      await executionManager.install(executionAdapter.descriptor.id, userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.network});
      await expectLater(executionManager.executeTool(runtimeId: executionAdapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'example.com'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: false), throwsA(isA<PolicyException>()));
      await expectLater(executionManager.executeTool(runtimeId: executionAdapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'example.com'},
          requiredCapabilities: const {RuntimeCapability.filesystemRead}, networkAuthorized: true), throwsA(isA<RuntimeExecutionException>()));
      expect(executionAdapter.executions, 0);
      executionManager.dispose();
    });

    test('rejects invalid input/output size and audits invalid output', () async {
      final smallInput = _ExecutionAdapter(maxInputBytes: 8);
      final inputManager = RuntimeManager(environment: environment, store: _Store(), adapters: [smallInput], supportDirectoryProvider: () async => root);
      await inputManager.install(smallInput.descriptor.id, userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.network});
      await expectLater(inputManager.executeTool(runtimeId: smallInput.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'example.com'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true), throwsA(isA<RuntimeExecutionException>()));
      expect(smallInput.executions, 0);
      inputManager.dispose();

      final largeOutput = _ExecutionAdapter(output: {'large': List.filled(256, 'x')});
      final outputManager = RuntimeManager(environment: environment, store: _Store(), adapters: [largeOutput], supportDirectoryProvider: () async => root);
      await outputManager.install(largeOutput.descriptor.id, userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.network});
      await expectLater(outputManager.executeTool(runtimeId: largeOutput.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true), throwsA(isA<RuntimeExecutionException>()));
      expect(outputManager.auditEvents.map((event) => event['action']), contains('tool-invalid-output'));
      outputManager.dispose();
    });

    test('enforces timeout and cancellation with cleanup', () async {
      final slow = _ExecutionAdapter(delay: const Duration(seconds: 1), maxExecution: const Duration(milliseconds: 30));
      final timeoutManager = RuntimeManager(environment: environment, store: _Store(), adapters: [slow], supportDirectoryProvider: () async => root);
      await timeoutManager.install(slow.descriptor.id, userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.network});
      await expectLater(timeoutManager.executeTool(runtimeId: slow.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true), throwsA(isA<TimeoutException>()));
      expect(timeoutManager.stateFor(slow.descriptor.id)?.lifecycle, RuntimeLifecycle.stopped);
      timeoutManager.dispose();

      final cancellable = _ExecutionAdapter(delay: const Duration(seconds: 1));
      final cancelManager = RuntimeManager(environment: environment, store: _Store(), adapters: [cancellable], supportDirectoryProvider: () async => root);
      await cancelManager.install(cancellable.descriptor.id, userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.network});
      final token = RuntimeCancellationToken();
      final pending = cancelManager.executeTool(runtimeId: cancellable.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: token);
      Timer(const Duration(milliseconds: 20), token.cancel);
      await expectLater(pending, throwsA(isA<RuntimeExecutionCancelled>()));
      expect(cancelManager.auditEvents.map((event) => event['action']), contains('tool-cancelled'));
      cancelManager.dispose();
    });

    test('checks all Android ABIs and API level; Linux ARM64 is not treated as Android', () {
      final executionAdapter = _ExecutionAdapter();
      final wrongAbi = RuntimeManager(environment: environment.copyWith(deviceAbis: const ['x86_64'], abi: 'x86_64'), store: _Store(), adapters: [executionAdapter]);
      expect(wrongAbi.compatibilityProblem(executionAdapter.descriptor), contains('ABI'));
      final oldApi = RuntimeManager(environment: environment.copyWith(androidApiLevel: 28), store: _Store(), adapters: [executionAdapter]);
      expect(oldApi.compatibilityProblem(executionAdapter.descriptor), contains('Android API'));
      final linux = RuntimeManager(environment: const RuntimeEnvironment(platform: 'Linux', abi: 'aarch64', availableCapabilities: {RuntimeCapability.network}), store: _Store(), adapters: [executionAdapter]);
      expect(linux.compatibilityProblem(executionAdapter.descriptor), contains('platform'));
      wrongAbi.dispose(); oldApi.dispose(); linux.dispose();
    });
  });

  test('enforces approval, declared capability and adapter-backed lifecycle without arbitrary shell execution', () async {
    await expectLater(manager.install('runtime.fixture', userApproved: false, licenseAccepted: true), throwsStateError);
    await expectLater(manager.install('runtime.fixture', userApproved: true, licenseAccepted: true), throwsStateError);
    final installed = await manager.install('runtime.fixture', userApproved: true, licenseAccepted: true,
        grantedCapabilities: const {RuntimeCapability.filesystemRead});
    expect(installed.lifecycle, RuntimeLifecycle.installed);
    expect(adapter.installs, 1);
    expect(Directory('${root.path}/runtime_workspaces/runtime.fixture').existsSync(), isTrue);
    expect(File('${root.path}/runtime_workspaces/runtime.fixture/metadata').existsSync(), isTrue);
    final initialized = await manager.initializeRuntime('runtime.fixture', userApproved: true);
    expect(initialized.lifecycle, RuntimeLifecycle.initialized);
    await expectLater(manager.start('runtime.fixture', userApproved: true, policyAllowed: false), throwsStateError);
    expect((await manager.start('runtime.fixture', userApproved: true, policyAllowed: true)).lifecycle, RuntimeLifecycle.running);
    await expectLater(manager.uninstall('runtime.fixture', userApproved: true), throwsStateError);
    expect((await manager.stop('runtime.fixture', userApproved: true)).lifecycle, RuntimeLifecycle.stopped);
    expect((await manager.update('runtime.fixture', '1.1.0', userApproved: true, licenseAccepted: true)).installedVersion, '1.1.0');
    await manager.uninstall('runtime.fixture', userApproved: true);
    expect(manager.stateFor('runtime.fixture'), isNull);
    expect(Directory('${root.path}/runtime_workspaces/runtime.fixture').existsSync(), isFalse);
    for (var index = 0; index < 55; index++) {
      await manager.healthCheck('runtime.fixture');
    }
    expect(manager.auditEvents.length, greaterThan(100));
    final eventIds = manager.auditEvents.map((event) => event['eventId']).whereType<String>().toList();
    expect(eventIds.toSet(), hasLength(eventIds.length));
    expect(manager.auditEvents.map((event) => event['action']), containsAll(['install-start', 'uninstall-start']));
    final persistedAudit = store.value['audit'] as List;
    expect((persistedAudit.first as Map<String, Object?>)['eventId'], manager.auditEvents.first['eventId']);
  });

  test('rejects unknown ABI and missing capabilities and persists lifecycle state', () async {
    final unsupported = RuntimeManager(environment: const RuntimeEnvironment(platform: 'Android', abi: 'armeabi-v7a'), store: store,
        adapters: [adapter], supportDirectoryProvider: () async => root);
    expect(unsupported.compatibilityProblem(adapter.descriptor), contains('ABI'));
    unsupported.dispose();
    final unavailable = RuntimeManager(environment: const RuntimeEnvironment(platform: 'Android', abi: 'arm64-v8a', availableCapabilities: {}),
        store: store, adapters: [adapter], supportDirectoryProvider: () async => root);
    expect(unavailable.compatibilityProblem(adapter.descriptor), contains('filesystemRead'));
    unavailable.dispose();
    const linuxOnly = RuntimeDescriptor(
      id: 'runtime.linux', name: 'Linux Fixture', version: '1.0.0', license: 'MIT', supportedPlatforms: ['Linux'],
      supportedAbis: [], dependencies: [], requiredCapabilities: {},
      sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    );
    expect(manager.compatibilityProblem(linuxOnly), contains('platform'));
    final dependentManager = RuntimeManager(environment: const RuntimeEnvironment(platform: 'Android', abi: 'arm64-v8a'),
        store: _Store(), adapters: [_DependentAdapter()], supportDirectoryProvider: () async => root);
    await expectLater(
      dependentManager.install('runtime.dependent', userApproved: true, licenseAccepted: true,
          grantedCapabilities: const {RuntimeCapability.filesystemRead}),
      throwsStateError,
    );
    dependentManager.dispose();
    await manager.install('runtime.fixture', userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.filesystemRead});
    final restored = RuntimeManager(environment: const RuntimeEnvironment(platform: 'Android', abi: 'arm64-v8a'), store: store,
        adapters: [adapter], supportDirectoryProvider: () async => root);
    await restored.initializeRegistry();
    expect(restored.auditEvents.length, manager.auditEvents.length);
    final restoredIds = restored.auditEvents.map((event) => event['eventId']).whereType<String>().toList();
    expect(restoredIds.toSet(), hasLength(restoredIds.length));
    expect(restored.auditEvents.first['eventId'], manager.auditEvents.first['eventId']);
    expect(restored.stateFor('runtime.fixture')?.lifecycle, RuntimeLifecycle.installed);
    await restored.initializeRuntime('runtime.fixture', userApproved: true);
    expect((await restored.start('runtime.fixture', userApproved: true, policyAllowed: true)).lifecycle, RuntimeLifecycle.running);
    await restored.stop('runtime.fixture', userApproved: true);
    restored.dispose();
  });

  test('requires strict semantic version update and records health failure', () async {
    await manager.install('runtime.fixture', userApproved: true, licenseAccepted: true, grantedCapabilities: const {RuntimeCapability.filesystemRead});
    await expectLater(manager.update('runtime.fixture', 'latest', userApproved: true, licenseAccepted: true), throwsFormatException);
    adapter.healthy = false;
    expect((await manager.healthCheck('runtime.fixture')).lifecycle, RuntimeLifecycle.failed);
  });
}
