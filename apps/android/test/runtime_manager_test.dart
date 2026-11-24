import 'dart:io';

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
    expect(manager.auditEvents, isNotEmpty);
    expect(manager.auditEvents.length, lessThanOrEqualTo(100));
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
