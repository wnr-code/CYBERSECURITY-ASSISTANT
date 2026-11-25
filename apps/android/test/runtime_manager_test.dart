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

class _FailOnSaveNumberStore extends _Store {
  _FailOnSaveNumberStore(this.failAt);
  final int failAt;
  int saves = 0;
  @override
  Future<void> save(Map<String, Object?> snapshot) async {
    saves++;
    if (saves == failAt) throw StateError('controlled save failure');
    await super.save(snapshot);
  }
}

class _ScriptedStore extends _Store {
  bool Function(Map<String, Object?> snapshot)? failWhen;

  @override
  Future<void> save(Map<String, Object?> snapshot) async {
    if (failWhen?.call(snapshot) == true) throw StateError('Controlled persistence failure.');
    await super.save(snapshot);
  }
}

bool _snapshotHasAction(Map<String, Object?> snapshot, String action) {
  final audit = snapshot['audit'];
  return audit is List && audit.any((entry) => entry is Map && entry['action'] == action);
}

class _Adapter implements RuntimeAdapter {
  _Adapter();
  bool healthy = true;
  int installs = 0;
  int initializes = 0;
  int stops = 0;
  Object? stopFailure;
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
  Future<void> stop() async {
    stops++;
    if (stopFailure != null) throw stopFailure!;
  }
  @override
  Future<void> update(Directory directory, String version) async { updates++; }
  @override
  Future<void> uninstall(Directory directory) async { removals++; }
  @override
  Future<bool> healthCheck() async => healthy;
}

class _BundledAdapter extends _Adapter {
  @override
  RuntimeDescriptor get descriptor => const RuntimeDescriptor(
        id: 'runtime.bundled', name: 'Bundled Runtime', version: '1.0.0', license: 'MIT',
        supportedAbis: ['arm64-v8a'], dependencies: [], requiredCapabilities: {RuntimeCapability.filesystemRead},
        sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', bundled: true,
      );
}

class _InstallFailureAdapter extends _Adapter {
  @override
  Future<void> install(Directory directory) async => throw StateError('controlled install failure');
}

class _ExecutionAdapter extends _Adapter implements RuntimeExecutionAdapter {
  _ExecutionAdapter({
    this.output = const {'result': 'ok'},
    this.maxExecution = const Duration(milliseconds: 200),
    this.maxInputBytes = 128,
    this.failure,
  });
  final Map<String, Object?> output;
  final Duration maxExecution;
  final int maxInputBytes;
  final Object? failure;
  RuntimeToolRequest? lastRequest;
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
    lastRequest = request;
    if (failure != null) throw failure!;
    request.cancellationToken.throwIfCancelled();
    return output;
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}

class _ControlledExecutionAdapter extends _ExecutionAdapter {
  _ControlledExecutionAdapter() : super();

  final executionStarted = Completer<RuntimeToolRequest>();
  final executionResult = Completer<Map<String, Object?>>();
  final stopStarted = Completer<void>();
  final stopRelease = Completer<void>();
  bool holdStop = false;
  Object? stopFailure;

  @override
  Future<Map<String, Object?>> executeTool(RuntimeToolRequest request) {
    lastRequest = request;
    executions++;
    if (!executionStarted.isCompleted) executionStarted.complete(request);
    return executionResult.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (!stopStarted.isCompleted) stopStarted.complete();
    if (holdStop) await stopRelease.future;
    if (stopFailure != null) throw stopFailure!;
  }
}

RuntimeManager _controlledManager({
  required RuntimeExecutionAdapter adapter,
  required RuntimeStateStore store,
  required Directory root,
  required List<_ManualTimer> timers,
}) =>
    RuntimeManager(
      environment: const RuntimeEnvironment(
        platform: 'Android',
        abi: 'arm64-v8a',
        deviceAbis: ['arm64-v8a', 'armeabi-v7a'],
        androidApiLevel: 35,
        availableCapabilities: {RuntimeCapability.network, RuntimeCapability.filesystemRead},
      ),
      store: store,
      adapters: [adapter],
      supportDirectoryProvider: () async => root,
      timerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

Future<void> _installNetworkAdapter(RuntimeManager manager, RuntimeExecutionAdapter adapter) => manager.install(
      adapter.descriptor.id,
      userApproved: true,
      licenseAccepted: true,
      grantedCapabilities: const {RuntimeCapability.network},
    );

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

    test('technical runtime failure cleans up the adapter without cancelling the caller token', () async {
      final failing = _ExecutionAdapter(failure: const RuntimeExecutionException('fixture runtime failure'));
      final failingManager = RuntimeManager(
        environment: environment,
        store: _Store(),
        adapters: [failing],
        supportDirectoryProvider: () async => root,
      );
      await failingManager.install(
        failing.descriptor.id,
        userApproved: true,
        licenseAccepted: true,
        grantedCapabilities: const {RuntimeCapability.network},
      );
      final callerToken = RuntimeCancellationToken();

      await expectLater(
        failingManager.executeTool(
          runtimeId: failing.descriptor.id,
          toolId: 'dns_lookup',
          input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network},
          networkAuthorized: true,
          cancellationToken: callerToken,
        ),
        throwsA(isA<RuntimeExecutionException>()),
      );

      expect(callerToken.isCancelled, isFalse);
      expect(failing.lastRequest?.cancellationToken.isCancelled, isTrue);
      expect(failingManager.stateFor(failing.descriptor.id)?.lifecycle, RuntimeLifecycle.stopped);
      expect(failingManager.auditEvents.map((event) => event['action']), contains('tool-RuntimeExecutionException'));
      expect(failingManager.lastExecutionReport?.outcome, RuntimeExecutionOutcome.failed);
      expect(failingManager.lastExecutionReport?.terminalAuditSaveConfirmed, isTrue);
      expect(callerToken.debugListenerCount, 0);
      failingManager.dispose();
    });

    test('timeout wins over cancellation arriving during held cleanup', () async {
      final adapter = _ControlledExecutionAdapter()..holdStop = true;
      final timers = <_ManualTimer>[];
      final testManager = RuntimeManager(
        environment: environment,
        store: _Store(),
        adapters: [adapter],
        supportDirectoryProvider: () async => root,
        timerFactory: (duration, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      await testManager.install(adapter.descriptor.id, userApproved: true, licenseAccepted: true,
          grantedCapabilities: const {RuntimeCapability.network});
      final token = RuntimeCancellationToken();
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: token);
      await adapter.executionStarted.future;

      timers.lastWhere((timer) => timer.isActive).fire();
      await adapter.stopStarted.future;
      expect(token.debugListenerCount, 0, reason: 'The caller subscription is disposed before cleanup awaits.');
      token.cancel();
      adapter.stopRelease.complete();

      await expectLater(pending, throwsA(isA<TimeoutException>()));
      expect(testManager.auditEvents.map((event) => event['action']), contains('tool-timeout'));
      expect(testManager.auditEvents.map((event) => event['action']), isNot(contains('tool-cancelled')));
      expect(testManager.stateFor(adapter.descriptor.id)?.lifecycle, RuntimeLifecycle.stopped);
      expect(token.debugListenerCount, 0);
      testManager.dispose();
    });

    test('completion wins over cancellation arriving during stop', () async {
      final adapter = _ControlledExecutionAdapter()..holdStop = true;
      final timers = <_ManualTimer>[];
      final testManager = RuntimeManager(
        environment: environment,
        store: _Store(),
        adapters: [adapter],
        supportDirectoryProvider: () async => root,
        timerFactory: (duration, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      await testManager.install(adapter.descriptor.id, userApproved: true, licenseAccepted: true,
          grantedCapabilities: const {RuntimeCapability.network});
      final token = RuntimeCancellationToken();
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: token);
      await adapter.executionStarted.future;
      adapter.executionResult.complete(const {'result': 'ok'});
      await adapter.stopStarted.future;

      token.cancel();
      expect(token.debugListenerCount, 0);
      adapter.stopRelease.complete();
      final result = await pending;

      expect(result.output, {'result': 'ok'});
      expect(testManager.auditEvents.map((event) => event['action']), contains('tool-complete'));
      expect(testManager.auditEvents.map((event) => event['action']), isNot(contains('tool-cancelled')));
      expect(testManager.stateFor(adapter.descriptor.id)?.lifecycle, RuntimeLifecycle.stopped);
      testManager.dispose();
    });

    test('explicit cancellation wins before the deadline and disposes its listener', () async {
      final adapter = _ControlledExecutionAdapter();
      final timers = <_ManualTimer>[];
      final testManager = RuntimeManager(
        environment: environment,
        store: _Store(),
        adapters: [adapter],
        supportDirectoryProvider: () async => root,
        timerFactory: (duration, callback) {
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      await testManager.install(adapter.descriptor.id, userApproved: true, licenseAccepted: true,
          grantedCapabilities: const {RuntimeCapability.network});
      final token = RuntimeCancellationToken();
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: token);
      await adapter.executionStarted.future;

      final executionDeadline = timers.lastWhere((timer) => timer.isActive);
      token.cancel();
      await expectLater(pending, throwsA(isA<RuntimeExecutionCancelled>()));
      executionDeadline.fire(); // A cancelled deadline cannot replace the winner.
      expect(testManager.auditEvents.map((event) => event['action']), contains('tool-cancelled'));
      expect(testManager.auditEvents.map((event) => event['action']), isNot(contains('tool-timeout')));
      expect(adapter.lastRequest?.cancellationToken.isCancelled, isTrue);
      expect(token.debugListenerCount, 0);
      testManager.dispose();
    });

    test('stop failure after success preserves success and reports cleanup failure', () async {
      final adapter = _ControlledExecutionAdapter()..stopFailure = StateError('stop rejected');
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: adapter, store: _Store(), root: root, timers: timers);
      await _installNetworkAdapter(testManager, adapter);
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true);
      await adapter.executionStarted.future;
      adapter.executionResult.complete(const {'result': 'ok'});

      final result = await pending;
      final report = result.report!;
      expect(report.outcome, RuntimeExecutionOutcome.success);
      expect(report.cleanupOutcome, RuntimeCleanupOutcome.failed);
      expect(report.cleanupErrorType, 'StateError');
      expect(testManager.stateFor(adapter.descriptor.id)?.lifecycle, RuntimeLifecycle.failed);
      expect(testManager.stateFor(adapter.descriptor.id)?.lastError, 'Runtime cleanup failed.');
      expect(testManager.auditEvents.map((event) => event['action']), containsAll(['tool-complete', 'tool-cleanup-failed']));
      testManager.dispose();
    });

    test('stop failure after timeout preserves timeout and keeps lifecycle failed', () async {
      final adapter = _ControlledExecutionAdapter()..stopFailure = StateError('stop rejected');
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: adapter, store: _Store(), root: root, timers: timers);
      await _installNetworkAdapter(testManager, adapter);
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true);
      await adapter.executionStarted.future;
      timers.lastWhere((timer) => timer.isActive).fire();
      await expectLater(pending, throwsA(isA<TimeoutException>()));

      final report = testManager.lastExecutionReport!;
      expect(report.outcome, RuntimeExecutionOutcome.timeout);
      expect(report.cleanupOutcome, RuntimeCleanupOutcome.failed);
      expect(testManager.stateFor(adapter.descriptor.id)?.lifecycle, RuntimeLifecycle.failed);
      expect(testManager.auditEvents.map((event) => event['action']), containsAll(['tool-timeout', 'tool-cleanup-failed']));
      testManager.dispose();
    });

    test('stop failure after caller cancellation preserves cancellation and keeps lifecycle failed', () async {
      final adapter = _ControlledExecutionAdapter()..stopFailure = StateError('stop rejected');
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: adapter, store: _Store(), root: root, timers: timers);
      await _installNetworkAdapter(testManager, adapter);
      final callerToken = RuntimeCancellationToken();
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: callerToken);
      await adapter.executionStarted.future;
      callerToken.cancel();
      await expectLater(pending, throwsA(isA<RuntimeExecutionCancelled>()));

      final report = testManager.lastExecutionReport!;
      expect(report.outcome, RuntimeExecutionOutcome.cancelled);
      expect(report.cleanupOutcome, RuntimeCleanupOutcome.failed);
      expect(callerToken.debugListenerCount, 0);
      expect(testManager.stateFor(adapter.descriptor.id)?.lifecycle, RuntimeLifecycle.failed);
      expect(testManager.auditEvents.map((event) => event['action']), containsAll(['tool-cancelled', 'tool-cleanup-failed']));
      testManager.dispose();
    });

    test('stop failure after technical failure preserves both separate results', () async {
      final adapter = _ControlledExecutionAdapter()..stopFailure = StateError('stop rejected');
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: adapter, store: _Store(), root: root, timers: timers);
      await _installNetworkAdapter(testManager, adapter);
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true);
      await adapter.executionStarted.future;
      adapter.executionResult.completeError(StateError('execution failed'));
      await expectLater(pending, throwsA(isA<RuntimeExecutionException>()));

      final report = testManager.lastExecutionReport!;
      expect(report.outcome, RuntimeExecutionOutcome.failed);
      expect(report.cleanupOutcome, RuntimeCleanupOutcome.failed);
      expect(testManager.stateFor(adapter.descriptor.id)?.lifecycle, RuntimeLifecycle.failed);
      expect(testManager.auditEvents.map((event) => event['action']), containsAll(['tool-StateError', 'tool-cleanup-failed']));
      testManager.dispose();
    });

    test('success exposes unconfirmed state persistence without changing execution outcome', () async {
      final adapter = _ControlledExecutionAdapter();
      final store = _ScriptedStore()
        ..failWhen = (snapshot) {
          final states = snapshot['states'];
          return _snapshotHasAction(snapshot, 'stopped') &&
              states is List && states.any((item) => item is Map && item['lifecycle'] == 'stopped');
        };
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: adapter, store: store, root: root, timers: timers);
      await _installNetworkAdapter(testManager, adapter);
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true);
      await adapter.executionStarted.future;
      adapter.executionResult.complete(const {'result': 'ok'});

      final result = await pending;
      final report = result.report!;
      expect(report.outcome, RuntimeExecutionOutcome.success);
      expect(report.terminalStateSaveConfirmed, isFalse);
      expect(report.terminalAuditSaveConfirmed, isTrue);
      expect(report.persistenceFullyConfirmed, isFalse);
      expect(report.persistenceFailures.any((failure) => failure.kind == RuntimePersistenceKind.state), isTrue);
      expect(report.persistenceFailures.every((failure) => failure.executionId == report.executionId), isTrue);
      expect(report.persistenceFailures.every((failure) => failure.runtimeId == adapter.descriptor.id && failure.toolId == 'dns_lookup'), isTrue);
      expect(testManager.stateFor(adapter.descriptor.id)?.lifecycle, RuntimeLifecycle.running,
          reason: 'A failed state write rolls back in memory; the manager must not claim stopped.');
      expect(testManager.auditEvents.map((event) => event['action']), contains('tool-complete'));
      testManager.dispose();
    });

    test('success exposes unconfirmed terminal audit persistence without changing outcome', () async {
      final adapter = _ControlledExecutionAdapter();
      final store = _ScriptedStore()..failWhen = (snapshot) => _snapshotHasAction(snapshot, 'tool-complete');
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: adapter, store: store, root: root, timers: timers);
      await _installNetworkAdapter(testManager, adapter);
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true);
      await adapter.executionStarted.future;
      adapter.executionResult.complete(const {'result': 'ok'});

      final result = await pending;
      expect(result.report?.outcome, RuntimeExecutionOutcome.success);
      expect(result.report?.terminalAuditSaveConfirmed, isFalse);
      expect(result.report?.terminalStateSaveConfirmed, isTrue);
      expect(result.report?.persistenceFailures.any((failure) => failure.kind == RuntimePersistenceKind.audit), isTrue);
      expect(testManager.auditEvents.map((event) => event['action']), isNot(contains('tool-complete')));
      testManager.dispose();
    });

    test('non-success outcome survives terminal audit persistence failure', () async {
      final adapter = _ControlledExecutionAdapter();
      final store = _ScriptedStore()..failWhen = (snapshot) => _snapshotHasAction(snapshot, 'tool-timeout');
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: adapter, store: store, root: root, timers: timers);
      await _installNetworkAdapter(testManager, adapter);
      final pending = testManager.executeTool(runtimeId: adapter.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true);
      await adapter.executionStarted.future;
      timers.lastWhere((timer) => timer.isActive).fire();
      await expectLater(pending, throwsA(isA<TimeoutException>()));

      final report = testManager.lastExecutionReport!;
      expect(report.outcome, RuntimeExecutionOutcome.timeout);
      expect(report.terminalAuditSaveConfirmed, isFalse);
      expect(report.terminalStateSaveConfirmed, isTrue);
      expect(report.persistenceFailures.any((failure) => failure.kind == RuntimePersistenceKind.audit), isTrue);
      expect(testManager.auditEvents.map((event) => event['action']), isNot(contains('tool-timeout')));
      testManager.dispose();
    });

    test('enforces timeout and cancellation with controlled futures and deadlines', () async {
      final slow = _ControlledExecutionAdapter();
      final timeoutTimers = <_ManualTimer>[];
      final timeoutManager = _controlledManager(adapter: slow, store: _Store(), root: root, timers: timeoutTimers);
      await _installNetworkAdapter(timeoutManager, slow);
      final timeoutToken = RuntimeCancellationToken();
      final timeoutPending = timeoutManager.executeTool(runtimeId: slow.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: timeoutToken);
      await slow.executionStarted.future;
      timeoutTimers.lastWhere((timer) => timer.isActive).fire();
      await expectLater(timeoutPending, throwsA(isA<TimeoutException>()));
      expect(timeoutToken.isCancelled, isFalse, reason: 'Timeout cleanup must not masquerade as caller cancellation.');
      expect(slow.lastRequest?.cancellationToken.isCancelled, isTrue, reason: 'Timeout cancels the child token.');
      expect(timeoutManager.auditEvents.map((event) => event['action']), contains('tool-timeout'));
      expect(timeoutManager.stateFor(slow.descriptor.id)?.lifecycle, RuntimeLifecycle.stopped);
      timeoutManager.dispose();

      final cancellable = _ControlledExecutionAdapter();
      final cancelTimers = <_ManualTimer>[];
      final cancelManager = _controlledManager(adapter: cancellable, store: _Store(), root: root, timers: cancelTimers);
      await _installNetworkAdapter(cancelManager, cancellable);
      final token = RuntimeCancellationToken();
      final cancelPending = cancelManager.executeTool(runtimeId: cancellable.descriptor.id, toolId: 'dns_lookup', input: const {'target': 'a'},
          requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: token);
      await cancellable.executionStarted.future;
      token.cancel();
      await expectLater(cancelPending, throwsA(isA<RuntimeExecutionCancelled>()));
      expect(token.isCancelled, isTrue, reason: 'An explicit caller cancellation remains observable.');
      expect(cancellable.lastRequest?.cancellationToken.isCancelled, isTrue);
      expect(token.debugListenerCount, 0);
      expect(cancelManager.auditEvents.map((event) => event['action']), contains('tool-cancelled'));
      cancelManager.dispose();
    });

    test('execution reports and persistence failures stay isolated by execution ID', () async {
      final executionAdapter = _ExecutionAdapter();
      var failOneCompletion = true;
      final reportStore = _ScriptedStore()
        ..failWhen = (snapshot) {
          if (failOneCompletion && _snapshotHasAction(snapshot, 'tool-complete')) {
            failOneCompletion = false;
            return true;
          }
          return false;
        };
      final testManager = _controlledManager(adapter: executionAdapter, store: reportStore, root: root, timers: <_ManualTimer>[]);
      await _installNetworkAdapter(testManager, executionAdapter);
      Future<RuntimeExecutionResult> run(String target) => testManager.executeTool(
            runtimeId: executionAdapter.descriptor.id,
            toolId: 'dns_lookup',
            input: {'target': target},
            requiredCapabilities: const {RuntimeCapability.network},
            networkAuthorized: true,
          );
      final first = await run('first');
      final second = await run('second');
      expect(first.report!.executionId, isNot(second.report!.executionId));
      expect(first.report!.persistenceFailures, isNotEmpty);
      expect(first.report!.persistenceFailures.every((failure) => failure.executionId == first.report!.executionId), isTrue);
      expect(second.report!.persistenceFailures, isEmpty);
      expect(testManager.reportForExecution(first.report!.executionId), same(first.report));
      expect(testManager.reportForExecution(second.report!.executionId), same(second.report));
      expect(testManager.auditEvents.where((event) => event['action'] == 'tool-complete').map((event) => event['executionId']),
          [second.report!.executionId, first.report!.executionId]);
      testManager.dispose();
    });

    test('synchronously admits only one near-simultaneous execution', () async {
      final executionAdapter = _ControlledExecutionAdapter();
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: executionAdapter, store: _Store(), root: root, timers: timers);
      await _installNetworkAdapter(testManager, executionAdapter);
      final first = testManager.executeTool(
        runtimeId: executionAdapter.descriptor.id,
        toolId: 'dns_lookup',
        input: const {'target': 'first'},
        requiredCapabilities: const {RuntimeCapability.network},
        networkAuthorized: true,
      );
      final second = testManager.executeTool(
        runtimeId: executionAdapter.descriptor.id,
        toolId: 'dns_lookup',
        input: const {'target': 'second'},
        requiredCapabilities: const {RuntimeCapability.network},
        networkAuthorized: true,
      );
      await expectLater(second, throwsA(isA<RuntimeExecutionException>()));
      await executionAdapter.executionStarted.future;
      executionAdapter.executionResult.complete(const {'result': 'accepted'});
      final result = await first;
      expect(result.output['result'], 'accepted');
      expect(executionAdapter.executions, 1);
      expect(result.report?.executionId, isNotEmpty);
      testManager.dispose();
    });

    test('direct stop is rejected during active execution without racing adapter cleanup', () async {
      final executionAdapter = _ControlledExecutionAdapter();
      final timers = <_ManualTimer>[];
      final testManager = _controlledManager(adapter: executionAdapter, store: _Store(), root: root, timers: timers);
      await _installNetworkAdapter(testManager, executionAdapter);
      final pending = testManager.executeTool(
        runtimeId: executionAdapter.descriptor.id,
        toolId: 'dns_lookup',
        input: const {'target': 'active'},
        requiredCapabilities: const {RuntimeCapability.network},
        networkAuthorized: true,
      );
      await executionAdapter.executionStarted.future;
      await expectLater(testManager.stop(executionAdapter.descriptor.id, userApproved: true), throwsStateError);
      expect(executionAdapter.stops, 0);
      executionAdapter.executionResult.complete(const {'result': 'done'});
      await pending;
      expect(executionAdapter.stops, 1, reason: 'Only execution-owned cleanup should stop the adapter.');
      testManager.dispose();
    });

    test('working-directory failure leaves admission available for the next run', () async {
      final executionAdapter = _ExecutionAdapter();
      var failDirectory = false;
      final testManager = RuntimeManager(
        environment: environment,
        store: _Store(),
        adapters: [executionAdapter],
        supportDirectoryProvider: () async {
          if (failDirectory) throw StateError('controlled directory failure');
          return root;
        },
      );
      await _installNetworkAdapter(testManager, executionAdapter);
      failDirectory = true;
      await expectLater(
        testManager.executeTool(
          runtimeId: executionAdapter.descriptor.id,
          toolId: 'dns_lookup',
          input: const {'target': 'first'},
          requiredCapabilities: const {RuntimeCapability.network},
          networkAuthorized: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(testManager.lastExecutionReport?.cleanupOutcome, RuntimeCleanupOutcome.notAttempted);
      failDirectory = false;
      final result = await testManager.executeTool(
        runtimeId: executionAdapter.descriptor.id,
        toolId: 'dns_lookup',
        input: const {'target': 'second'},
        requiredCapabilities: const {RuntimeCapability.network},
        networkAuthorized: true,
      );
      expect(result.output['result'], 'ok');
      testManager.dispose();
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

  test('registry initialization retry persists without installing bundled adapter twice', () async {
    final bundled = _BundledAdapter();
    final retryStore = _FailOnSaveNumberStore(2);
    final registryManager = RuntimeManager(
      environment: const RuntimeEnvironment(platform: 'Android', abi: 'arm64-v8a'),
      store: retryStore,
      adapters: [bundled],
      supportDirectoryProvider: () async => root,
    );
    await expectLater(registryManager.initializeRegistry(), throwsA(isA<StateError>()));
    expect(bundled.installs, 1);
    expect(registryManager.persistenceFailures.last.kind, RuntimePersistenceKind.registry);
    await registryManager.initializeRegistry();
    expect(bundled.installs, 1);
    expect(registryManager.stateFor(bundled.descriptor.id)?.lifecycle, RuntimeLifecycle.installed);
    registryManager.dispose();
  });

  test('install-start audit failure does not invoke adapter or mark runtime installed', () async {
    final failingStore = _ScriptedStore()..failWhen = (snapshot) => _snapshotHasAction(snapshot, 'install-start');
    final installAdapter = _Adapter();
    final installManager = RuntimeManager(
      environment: const RuntimeEnvironment(platform: 'Android', abi: 'arm64-v8a'),
      store: failingStore,
      adapters: [installAdapter],
      supportDirectoryProvider: () async => root,
    );
    await expectLater(
      installManager.install(installAdapter.descriptor.id, userApproved: true, licenseAccepted: true,
          grantedCapabilities: const {RuntimeCapability.filesystemRead}),
      throwsA(isA<StateError>()),
    );
    expect(installAdapter.installs, 0);
    expect(installManager.stateFor(installAdapter.descriptor.id)?.lifecycle, RuntimeLifecycle.failed);
    installManager.dispose();
  });

  test('adapter install exception never leaves runtime marked installed', () async {
    final installAdapter = _InstallFailureAdapter();
    final installManager = RuntimeManager(
      environment: const RuntimeEnvironment(platform: 'Android', abi: 'arm64-v8a'),
      store: _Store(),
      adapters: [installAdapter],
      supportDirectoryProvider: () async => root,
    );
    await expectLater(
      installManager.install(installAdapter.descriptor.id, userApproved: true, licenseAccepted: true,
          grantedCapabilities: const {RuntimeCapability.filesystemRead}),
      throwsA(isA<StateError>()),
    );
    expect(installManager.stateFor(installAdapter.descriptor.id)?.lifecycle, RuntimeLifecycle.failed);
    expect(installManager.stateFor(installAdapter.descriptor.id)?.installedVersion, isNull);
    installManager.dispose();
  });

  test('direct lifecycle stop failure is recorded and never reports stopped', () async {
    await manager.install('runtime.fixture', userApproved: true, licenseAccepted: true,
        grantedCapabilities: const {RuntimeCapability.filesystemRead});
    adapter.stopFailure = StateError('stop rejected');

    await expectLater(manager.stop('runtime.fixture', userApproved: true), throwsA(isA<StateError>()));

    expect(manager.stateFor('runtime.fixture')?.lifecycle, RuntimeLifecycle.failed);
    expect(manager.stateFor('runtime.fixture')?.lastError, 'Runtime cleanup failed.');
    expect(manager.auditEvents.map((event) => event['action']), contains('runtime-stop-cleanup-failed'));
    expect(manager.persistenceFailures, isEmpty);
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
