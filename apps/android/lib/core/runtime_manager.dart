import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_self_protection.dart';
import 'diagnostics.dart';
import 'policy_engine.dart';
import 'security_tools.dart';

enum RuntimeLifecycle { available, installed, initialized, running, stopped, failed, incompatible }
enum RuntimeCapability { filesystemRead, filesystemWrite, network, processExecution, nativeCode }

class RuntimeDescriptor {
  const RuntimeDescriptor({
    required this.id,
    required this.name,
    required this.version,
    this.license,
    required this.supportedAbis,
    this.supportedPlatforms = const ['Android'],
    required this.dependencies,
    required this.requiredCapabilities,
    required this.sha256,
    this.officialSource = 'Bundled/runtime adapter registry',
    this.resourceLimit = const RuntimeResourceLimit(),
    this.bundled = false,
    this.minAndroidApi,
    this.supportedToolIds = const [],
  });
  final String id;
  final String name;
  final String version;
  final String? license;
  final List<String> supportedAbis;
  final List<String> supportedPlatforms;
  final List<String> dependencies;
  final Set<RuntimeCapability> requiredCapabilities;
  /// Expected metadata only. This registry installs no remote artifact and does not claim signature verification.
  final String sha256;
  final String officialSource;
  final RuntimeResourceLimit resourceLimit;
  final bool bundled;
  final int? minAndroidApi;
  final List<String> supportedToolIds;

  bool get metadataValid => RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(id) &&
      version.isNotEmpty &&
      (license?.trim().isNotEmpty ?? true) &&
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256) && officialSource.isNotEmpty &&
      (minAndroidApi == null || minAndroidApi! > 0) &&
      supportedToolIds.toSet().length == supportedToolIds.length &&
      supportedToolIds.every((toolId) => RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(toolId));
}

/// Declared adapter budgets are validated, but cannot enforce OS process/memory quotas without a concrete sandboxed runtime.
class RuntimeResourceLimit {
  const RuntimeResourceLimit({this.maxMemoryMb = 64, this.maxExecution = const Duration(seconds: 10), this.maxInputBytes = 65536, this.maxOutputBytes = 65536});
  final int maxMemoryMb;
  final Duration maxExecution;
  final int maxInputBytes;
  final int maxOutputBytes;
  bool get valid => maxMemoryMb > 0 && maxMemoryMb <= 512 && maxExecution > Duration.zero && maxExecution <= const Duration(minutes: 2) && maxInputBytes > 0 && maxInputBytes <= 1048576 && maxOutputBytes > 0 && maxOutputBytes <= 1048576;
}

class RuntimeEnvironment {
  const RuntimeEnvironment({
    required this.platform,
    this.abi,
    this.deviceAbis = const [],
    this.androidApiLevel,
    this.availableCapabilities = const {RuntimeCapability.filesystemRead, RuntimeCapability.filesystemWrite},
  });

  final String platform;
  /// First reported ABI for backwards compatibility with callers using the original field.
  final String? abi;
  final List<String> deviceAbis;
  final int? androidApiLevel;
  final Set<RuntimeCapability> availableCapabilities;

  RuntimeEnvironment copyWith({String? platform, String? abi, List<String>? deviceAbis, int? androidApiLevel, Set<RuntimeCapability>? availableCapabilities}) =>
      RuntimeEnvironment(
        platform: platform ?? this.platform,
        abi: abi ?? this.abi,
        deviceAbis: deviceAbis ?? this.deviceAbis,
        androidApiLevel: androidApiLevel ?? this.androidApiLevel,
        availableCapabilities: availableCapabilities ?? this.availableCapabilities,
      );

  static Future<RuntimeEnvironment> detect() async {
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        final abis = List<String>.unmodifiable(info.supportedAbis);
        return RuntimeEnvironment(
          platform: 'Android',
          abi: abis.isEmpty ? null : abis.first,
          deviceAbis: abis,
          androidApiLevel: info.version.sdkInt,
          availableCapabilities: const {
            RuntimeCapability.filesystemRead,
            RuntimeCapability.filesystemWrite,
            RuntimeCapability.network,
          },
        );
      } catch (_) {
        return const RuntimeEnvironment(
          platform: 'Android',
          availableCapabilities: {RuntimeCapability.filesystemRead, RuntimeCapability.filesystemWrite, RuntimeCapability.network},
        );
      }
    }
    return RuntimeEnvironment(
      platform: Platform.operatingSystem,
      availableCapabilities: const {RuntimeCapability.filesystemRead, RuntimeCapability.filesystemWrite, RuntimeCapability.network},
    );
  }
}

class RuntimeState {
  const RuntimeState({required this.id, required this.lifecycle, required this.installedVersion, required this.updatedAt, this.lastHealthCheck, this.lastError});
  final String id;
  final RuntimeLifecycle lifecycle;
  final String? installedVersion;
  final DateTime updatedAt;
  final DateTime? lastHealthCheck;
  final String? lastError;
  Map<String, Object?> toJson() => {
        'id': id,
        'lifecycle': lifecycle.name,
        'installedVersion': installedVersion,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'lastHealthCheck': lastHealthCheck?.toUtc().toIso8601String(),
        'lastError': lastError,
      };
}

enum RuntimeDiscoveryStatus { available, notInstalled, unsupported, environmentRequired }

class RuntimeDiscovery {
  const RuntimeDiscovery({required this.descriptor, required this.status, this.reason, this.state});
  final RuntimeDescriptor descriptor;
  final RuntimeDiscoveryStatus status;
  final String? reason;
  final RuntimeState? state;
}

class RuntimeCancellationToken implements ToolCancellation {
  final Completer<void> _cancelled = Completer<void>();
  final Set<void Function()> _listeners = {};

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  @visibleForTesting
  int get debugListenerCount => _listeners.length;

  RuntimeCancellationSubscription subscribe(void Function() listener) {
    if (isCancelled) {
      listener();
      return RuntimeCancellationSubscription._closed();
    }
    _listeners.add(listener);
    return RuntimeCancellationSubscription._(this, listener);
  }

  void cancel() {
    if (_cancelled.isCompleted) return;
    _cancelled.complete();
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void _removeListener(void Function() listener) => _listeners.remove(listener);

  void throwIfCancelled() {
    if (isCancelled) throw const RuntimeExecutionCancelled();
  }
}

/// A removable callback registration for a [RuntimeCancellationToken].
class RuntimeCancellationSubscription {
  RuntimeCancellationSubscription._(this._token, this._listener);
  RuntimeCancellationSubscription._closed() : _token = null, _listener = null;

  RuntimeCancellationToken? _token;
  final void Function()? _listener;

  void dispose() {
    final token = _token;
    _token = null;
    final listener = _listener;
    if (token != null && listener != null) token._removeListener(listener);
  }
}

class RuntimeExecutionCancelled implements Exception {
  const RuntimeExecutionCancelled({this.report});
  final RuntimeExecutionReport? report;
  @override
  String toString() => 'Runtime execution was cancelled.';
}

class RuntimeExecutionException implements Exception {
  const RuntimeExecutionException(this.message, {this.report});
  final String message;
  final RuntimeExecutionReport? report;
  @override
  String toString() => message;
}

class RuntimeExecutionTimeout extends TimeoutException {
  RuntimeExecutionTimeout(Duration? duration, this.report)
      : super('Runtime execution timed out.', duration);
  final RuntimeExecutionReport report;
}

class RuntimeToolRequest {
  const RuntimeToolRequest({
    required this.toolId,
    required this.input,
    required this.requiredCapabilities,
    required this.networkAuthorized,
    required this.cancellationToken,
  });
  final String toolId;
  final Map<String, Object?> input;
  final Set<RuntimeCapability> requiredCapabilities;
  final bool networkAuthorized;
  final RuntimeCancellationToken cancellationToken;
}

abstract interface class RuntimeExecutionAdapter implements RuntimeAdapter {
  Future<Map<String, Object?>> executeTool(RuntimeToolRequest request);
}

enum RuntimeExecutionOutcome { success, failed, timeout, cancelled }
enum RuntimeCleanupOutcome { notAttempted, succeeded, failed }
enum RuntimePersistenceKind { registry, state, audit }

class RuntimePersistenceFailure {
  const RuntimePersistenceFailure({
    required this.sequence,
    required this.kind,
    required this.operation,
    required this.errorType,
    required this.at,
    this.executionId,
    this.runtimeId,
    this.toolId,
  });

  final int sequence;
  final RuntimePersistenceKind kind;
  final String operation;
  final String errorType;
  final DateTime at;
  final String? executionId;
  final String? runtimeId;
  final String? toolId;
}

/// Ephemeral execution report: this reports what the runtime could confirm in
/// memory; it is not itself durable and never claims failed writes succeeded.
class RuntimeExecutionReport {
  RuntimeExecutionReport({
    required this.executionId,
    required this.runtimeId,
    required this.toolId,
    required this.outcome,
    required this.cleanupOutcome,
    this.cleanupErrorType,
    required this.terminalStateSaveConfirmed,
    required this.terminalAuditSaveConfirmed,
    required List<RuntimePersistenceFailure> persistenceFailures,
  }) : persistenceFailures = List.unmodifiable(persistenceFailures);

  final String executionId;
  final String runtimeId;
  final String toolId;
  final RuntimeExecutionOutcome outcome;
  final RuntimeCleanupOutcome cleanupOutcome;
  final String? cleanupErrorType;
  final bool terminalStateSaveConfirmed;
  final bool terminalAuditSaveConfirmed;
  final List<RuntimePersistenceFailure> persistenceFailures;

  bool get persistenceFullyConfirmed =>
      terminalStateSaveConfirmed && terminalAuditSaveConfirmed && persistenceFailures.isEmpty;
}

class RuntimeExecutionResult {
  const RuntimeExecutionResult({required this.runtimeId, required this.toolId, required this.output, required this.duration, this.report});
  final String runtimeId;
  final String toolId;
  final Map<String, Object?> output;
  final Duration duration;
  final RuntimeExecutionReport? report;
}

enum _RuntimeTerminalKind { success, failed, timeout, cancelled }

class _RuntimeTerminalOutcome {
  const _RuntimeTerminalOutcome._(this.kind, {this.output, this.error, this.stackTrace, this.timeout});

  const _RuntimeTerminalOutcome.success(Map<String, Object?> output)
      : this._(_RuntimeTerminalKind.success, output: output);
  const _RuntimeTerminalOutcome.failed(Object error, StackTrace stackTrace)
      : this._(_RuntimeTerminalKind.failed, error: error, stackTrace: stackTrace);
  const _RuntimeTerminalOutcome.timeout(Duration timeout)
      : this._(_RuntimeTerminalKind.timeout, timeout: timeout);
  const _RuntimeTerminalOutcome.cancelled() : this._(_RuntimeTerminalKind.cancelled);

  final _RuntimeTerminalKind kind;
  final Map<String, Object?>? output;
  final Object? error;
  final StackTrace? stackTrace;
  final Duration? timeout;

  Object asException() => switch (kind) {
        _RuntimeTerminalKind.cancelled => const RuntimeExecutionCancelled(),
        _RuntimeTerminalKind.timeout => TimeoutException('Runtime execution timed out.', timeout),
        _RuntimeTerminalKind.failed => error is RuntimeExecutionException
            ? error as RuntimeExecutionException
            : RuntimeExecutionException(sanitizeDiagnosticText(error.toString())),
        _RuntimeTerminalKind.success => StateError('A successful terminal outcome has no exception.'),
      };
}

class _RuntimeTerminalArbiter {
  _RuntimeTerminalArbiter(this.executionToken);

  final RuntimeCancellationToken executionToken;
  _RuntimeTerminalOutcome? _outcome;
  final Completer<_RuntimeTerminalOutcome> _completed = Completer<_RuntimeTerminalOutcome>();
  RuntimeCancellationSubscription? _cancellationSubscription;
  Timer? _deadline;

  bool get isSettled => _outcome != null;
  _RuntimeTerminalOutcome? get outcome => _outcome;
  Future<_RuntimeTerminalOutcome> get future => _completed.future;

  void attachCancellationSubscription(RuntimeCancellationSubscription subscription) {
    if (isSettled) {
      subscription.dispose();
    } else {
      _cancellationSubscription = subscription;
    }
  }

  void attachDeadline(Timer deadline) {
    if (isSettled) {
      deadline.cancel();
    } else {
      _deadline?.cancel();
      _deadline = deadline;
    }
  }

  bool trySet(_RuntimeTerminalOutcome outcome) {
    if (_outcome != null) return false;
    _outcome = outcome;
    _deadline?.cancel();
    _cancellationSubscription?.dispose();
    if (outcome.kind != _RuntimeTerminalKind.success) executionToken.cancel();
    _completed.complete(outcome);
    return true;
  }
}

class MemoryRuntimeStateStore implements RuntimeStateStore {
  Map<String, Object?> _snapshot = {};
  @override
  Future<Map<String, Object?>> load() async => Map<String, Object?>.from(_snapshot);
  @override
  Future<void> save(Map<String, Object?> snapshot) async {
    _snapshot = Map<String, Object?>.from(snapshot);
  }
}

abstract interface class RuntimeStateStore {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> snapshot);
}

class FileRuntimeStateStore implements RuntimeStateStore {
  FileRuntimeStateStore({Future<Directory> Function()? directoryProvider}) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directoryProvider;
  Future<File> _file() async {
    final dir = await _directoryProvider();
    final root = Directory(p.join(dir.path, 'runtime_registry'));
    await root.create(recursive: true);
    return File(p.join(root.path, 'registry.json'));
  }

  @override
  Future<Map<String, Object?>> load() async {
    final file = await _file();
    if (!await file.exists()) return {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) throw const FormatException('Runtime registry is invalid.');
    return decoded;
  }

  @override
  Future<void> save(Map<String, Object?> snapshot) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(snapshot), flush: true);
    await temp.rename(file.path);
  }
}

abstract interface class RuntimeAdapter {
  RuntimeDescriptor get descriptor;
  Future<void> install(Directory isolatedWorkingDirectory);
  Future<void> initialize(Directory isolatedWorkingDirectory);
  Future<void> stop();
  Future<void> update(Directory isolatedWorkingDirectory, String version);
  Future<void> uninstall(Directory isolatedWorkingDirectory);
  Future<bool> healthCheck();
}

/// Timer seam used by runtime execution tests to advance deadlines deterministically.
typedef RuntimeTimerFactory = Timer Function(Duration duration, void Function() callback);

Timer _defaultTimerFactory(Duration duration, void Function() callback) => Timer(duration, callback);

/// Persistent lifecycle/permission boundary only. An empty adapter registry is intentional:
/// this app does not bundle or execute arbitrary Market downloads as a runtime.
class RuntimeManager extends ChangeNotifier {
  RuntimeManager({
    required this.environment,
    required this.store,
    Iterable<RuntimeAdapter> adapters = const [],
    PolicyEngine? policy,
    DateTime Function()? clock,
    Future<Directory> Function()? supportDirectoryProvider,
    RuntimeTimerFactory? timerFactory,
  })  : _clock = clock ?? DateTime.now,
        _policy = policy ?? PolicyEngine(),
        _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory,
        _timerFactory = timerFactory ?? _defaultTimerFactory {
    for (final adapter in adapters) {
      final descriptor = adapter.descriptor;
      if (!descriptor.metadataValid || !descriptor.resourceLimit.valid || _adapters.containsKey(descriptor.id)) {
        throw ArgumentError('Runtime adapter registry contains invalid or duplicate metadata.');
      }
      _adapters[descriptor.id] = adapter;
    }
  }

  final RuntimeEnvironment environment;
  final RuntimeStateStore store;
  final PolicyEngine _policy;
  static const AppSelfProtectionPolicy _selfProtection = AppSelfProtectionPolicy();
  final DateTime Function() _clock;
  final Future<Directory> Function() _supportDirectoryProvider;
  final RuntimeTimerFactory _timerFactory;
  final Map<String, RuntimeAdapter> _adapters = {};
  final Map<String, RuntimeState> _states = {};
  final Map<String, Set<RuntimeCapability>> _grants = {};
  static int _managerSequence = 0;
  static const int persistenceFailureHistoryLimit = 100;

  final List<Map<String, Object?>> _audit = [];
  final List<RuntimePersistenceFailure> _persistenceFailures = [];
  final Map<String, RuntimeExecutionReport> _executionReports = {};
  final int _managerId = ++_managerSequence;
  String? _activeExecutionId;
  String? _activeRuntimeId;
  String? _activeToolId;
  int _executionSequence = 0;
  int _auditSequence = 0;
  int _persistenceFailureSequence = 0;
  RuntimeExecutionReport? _lastExecutionReport;
  bool _initialized = false;
  bool _registrySnapshotLoaded = false;
  bool _registryMutation = false;
  Future<void>? _initialization;
  bool _busy = false;
  List<RuntimeState> get states => List.unmodifiable(_states.values);
  List<Map<String, Object?>> get auditEvents => List.unmodifiable(_audit.map((entry) => Map<String, Object?>.unmodifiable(entry)));
  /// Rolling history containing at most [persistenceFailureHistoryLimit] most recent failures.
  List<RuntimePersistenceFailure> get persistenceFailures => List.unmodifiable(_persistenceFailures);
  /// Compatibility/diagnostics view of the most recently completed execution; not a run lookup API.
  RuntimeExecutionReport? get lastExecutionReport => _lastExecutionReport;
  RuntimeExecutionReport? reportForExecution(String executionId) => _executionReports[executionId];

  String _newExecutionId() => 'runtime-exec-$_managerId-${++_executionSequence}';
  List<RuntimeDescriptor> get registered => List.unmodifiable(_adapters.values.map((adapter) => adapter.descriptor));
  /// Tool IDs exposed by concrete, reviewed execution adapters only. A descriptor
  /// without an executable adapter does not authorize dispatch.
  Set<String> get executableToolIds => {
        for (final adapter in _adapters.values)
          if (adapter is RuntimeExecutionAdapter) ...adapter.descriptor.supportedToolIds,
      };
  bool get busy => _busy;

  String? compatibilityProblem(RuntimeDescriptor descriptor) {
    if (!descriptor.metadataValid || !descriptor.resourceLimit.valid) return 'Runtime metadata or resource limits are invalid.';
    if (!descriptor.supportedPlatforms.any((platform) => platform.toLowerCase() == environment.platform.toLowerCase() || platform == 'Any')) return 'Runtime does not support this platform.';
    if (environment.platform.toLowerCase() == 'android' && descriptor.minAndroidApi != null) {
      final api = environment.androidApiLevel;
      if (api == null) return 'Android API level is unknown; runtime compatibility needs device information.';
      if (api < descriptor.minAndroidApi!) return 'Runtime requires Android API ${descriptor.minAndroidApi} or newer; detected API $api.';
    }
    if (environment.platform.toLowerCase() == 'android' && descriptor.supportedAbis.isNotEmpty && !descriptor.supportedAbis.contains('any')) {
      final deviceAbis = environment.deviceAbis.isNotEmpty ? environment.deviceAbis : (environment.abi == null ? const <String>[] : [environment.abi!]);
      if (deviceAbis.isEmpty) return 'Device ABI is unknown; ABI compatibility cannot be confirmed.';
      if (!deviceAbis.any(descriptor.supportedAbis.contains)) return 'Runtime does not support the device ABIs: ${deviceAbis.join(', ')}.';
    }
    final missing = descriptor.requiredCapabilities.difference(environment.availableCapabilities);
    if (missing.isNotEmpty) return 'Environment is missing capabilities: ${missing.map((item) => item.name).join(', ')}.';
    final missingDependencies = descriptor.dependencies.where((dependency) => !_adapters.containsKey(dependency)).toList();
    if (missingDependencies.isNotEmpty) return 'Environment requires runtime dependencies: ${missingDependencies.join(', ')}.';
    return null;
  }

  Future<List<RuntimeDiscovery>> discover() async {
    await initializeRegistry();
    return List.unmodifiable(_adapters.values.map((adapter) {
      final descriptor = adapter.descriptor;
      final dependencyNotReady = descriptor.dependencies.where((id) {
        final lifecycle = _states[id]?.lifecycle;
        return lifecycle != RuntimeLifecycle.installed && lifecycle != RuntimeLifecycle.initialized && lifecycle != RuntimeLifecycle.stopped;
      }).toList();
      final reason = dependencyNotReady.isNotEmpty
          ? 'Environment requires installed runtime dependencies: ${dependencyNotReady.join(', ')}.'
          : compatibilityProblem(descriptor);
      final state = _states[descriptor.id];
      final RuntimeDiscoveryStatus status;
      if (reason != null) {
        final unsupported = reason.contains('does not support') || reason.contains('requires Android API') || reason.contains('ABI');
        status = unsupported ? RuntimeDiscoveryStatus.unsupported : RuntimeDiscoveryStatus.environmentRequired;
      } else if (state == null) {
        status = RuntimeDiscoveryStatus.notInstalled;
      } else if (state.lifecycle == RuntimeLifecycle.failed || state.lifecycle == RuntimeLifecycle.incompatible) {
        status = RuntimeDiscoveryStatus.environmentRequired;
      } else {
        status = RuntimeDiscoveryStatus.available;
      }
      return RuntimeDiscovery(
        descriptor: descriptor,
        status: status,
        reason: reason ?? state?.lastError ?? (state?.lifecycle == RuntimeLifecycle.failed ? 'Runtime failed its most recent health or lifecycle check.' : null),
        state: state,
      );
    }));
  }

  Set<String> get availableRuntimeIds => {
        for (final adapter in _adapters.values)
          if (compatibilityProblem(adapter.descriptor) == null &&
              _states[adapter.descriptor.id] != null &&
              _states[adapter.descriptor.id]!.lifecycle != RuntimeLifecycle.failed &&
              _states[adapter.descriptor.id]!.lifecycle != RuntimeLifecycle.incompatible)
            adapter.descriptor.id,
      };

  RuntimeState? stateFor(String id) => _states[id];

  Future<void> initializeRegistry() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initializeRegistry().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initializeRegistry() async {
    if (_initialized) return;
    final snapshot = _registrySnapshotLoaded ? const <String, Object?>{} : await store.load();
    _registrySnapshotLoaded = true;
    final rawGrants = snapshot['grants'];
    if (rawGrants is Map<String, dynamic>) {
      for (final entry in rawGrants.entries) {
        if (!_adapters.containsKey(entry.key) || entry.value is! List) continue;
        _grants[entry.key] = (entry.value as List)
            .whereType<String>()
            .map((name) => RuntimeCapability.values.where((capability) => capability.name == name))
            .where((matches) => matches.isNotEmpty)
            .map((matches) => matches.first)
            .toSet();
      }
    }
    final rawStates = snapshot['states'];
    if (rawStates is List) {
      for (final raw in rawStates) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'];
        if (id is! String || !_adapters.containsKey(id)) continue;
        final descriptor = _adapters[id]!.descriptor;
        final version = raw['installedVersion'];
        final date = DateTime.tryParse(raw['updatedAt'] is String ? raw['updatedAt'] as String : '')?.toUtc() ?? _clock().toUtc();
        final lifecycleName = raw['lifecycle'];
        final lifecycleMatches = RuntimeLifecycle.values.where((item) => item.name == lifecycleName);
        final loadedLifecycle = lifecycleMatches.isEmpty ? RuntimeLifecycle.stopped : lifecycleMatches.first;
        final lifecycle = loadedLifecycle == RuntimeLifecycle.running || loadedLifecycle == RuntimeLifecycle.initialized ? RuntimeLifecycle.stopped : loadedLifecycle;
        _states[id] = RuntimeState(id: id, lifecycle: lifecycle, installedVersion: version is String ? version : descriptor.version, updatedAt: date);
      }
    }
    final audit = snapshot['audit'];
    if (audit is List) {
      for (final item in audit.whereType<Map<String, dynamic>>()) {
        _audit.add(Map<String, Object?>.from(item));
        final eventId = item['eventId'];
        final match = eventId is String ? RegExp(r'^runtime-\d+-(\d+)$').firstMatch(eventId) : null;
        final sequence = int.tryParse(match?.group(1) ?? '');
        if (sequence != null && sequence > _auditSequence) _auditSequence = sequence;
      }
    }
    _registryMutation = true;
    try {
      for (final adapter in _adapters.values.where((item) => item.descriptor.bundled)) {
        final descriptor = adapter.descriptor;
        if (_states.containsKey(descriptor.id) || compatibilityProblem(descriptor) != null) continue;
        try {
          await adapter.install(await _workingDirectory(descriptor.id));
          _grants[descriptor.id] = Set.unmodifiable(descriptor.requiredCapabilities.intersection(environment.availableCapabilities));
          _states[descriptor.id] = RuntimeState(
            id: descriptor.id,
            lifecycle: RuntimeLifecycle.installed,
            installedVersion: descriptor.version,
            updatedAt: _clock().toUtc(),
          );
          await _record('bundled-adapter-installed', descriptor.id);
        } catch (error, stack) {
          DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
          _states[descriptor.id] = RuntimeState(
            id: descriptor.id,
            lifecycle: RuntimeLifecycle.failed,
            installedVersion: null,
            updatedAt: _clock().toUtc(),
            lastError: sanitizeDiagnosticText(error.runtimeType.toString()),
          );
          await _record('bundled-adapter-install-failed', descriptor.id);
        }
      }
    } finally {
      _registryMutation = false;
    }
    _registryMutation = true;
    try {
      await _persist();
    } catch (error) {
      _rememberPersistenceFailure(RuntimePersistenceKind.registry, 'initialize-registry', error);
      rethrow;
    } finally {
      _registryMutation = false;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<RuntimeState> install(String id, {required bool userApproved, required bool licenseAccepted, Set<RuntimeCapability> grantedCapabilities = const {}}) async {
    await initializeRegistry();
    final adapter = _requireAdapter(id);
    final descriptor = adapter.descriptor;
    if (!userApproved || !licenseAccepted) {
      DiagnosticReporter.recordGlobal(StateError('Runtime installation was denied because required consent was not granted.'), category: DiagnosticCategory.runtime);
      throw StateError('Explicit install and license approval are required.');
    }
    final reason = compatibilityProblem(descriptor);
    if (reason != null) {
      if (reason.contains('runtime dependencies:')) throw StateError(reason);
      return _set(id, RuntimeLifecycle.incompatible, error: reason);
    }
    final existing = _states[id];
    if (existing?.lifecycle == RuntimeLifecycle.running) throw StateError('Stop the runtime before reinstalling it.');
    if (existing?.lifecycle == RuntimeLifecycle.installed && existing?.installedVersion == descriptor.version) return existing!;
    final missingDependencies = descriptor.dependencies.where((dependency) {
      final state = _states[dependency];
      return !_adapters.containsKey(dependency) || (state?.lifecycle != RuntimeLifecycle.installed && state?.lifecycle != RuntimeLifecycle.stopped);
    }).toList();
    if (missingDependencies.isNotEmpty) throw StateError('Missing runtime dependencies: ${missingDependencies.join(', ')}.');
    if (descriptor.requiredCapabilities.difference(grantedCapabilities).isNotEmpty) throw StateError('Required capabilities were not explicitly granted.');
    if (grantedCapabilities.difference(descriptor.requiredCapabilities).isNotEmpty ||
        grantedCapabilities.difference(environment.availableCapabilities).isNotEmpty) {
      throw StateError('Only declared capabilities available in this environment may be granted.');
    }
    final directory = await _workingDirectory(id);
    return _withLifecycle(id, RuntimeLifecycle.failed, () async {
      await _record('install-start', id);
      try {
        await adapter.install(directory);
      } catch (error, stack) {
        DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
        await _record('install-failed', id);
        rethrow;
      }
      _grants[id] = Set.unmodifiable(grantedCapabilities);
      return _set(id, RuntimeLifecycle.installed, version: descriptor.version);
    });
  }

  Future<RuntimeState> initializeRuntime(String id, {required bool userApproved}) async {
    await initializeRegistry();
    if (!userApproved) {
      DiagnosticReporter.recordGlobal(StateError('Runtime initialization was denied because required consent was not granted.'), category: DiagnosticCategory.runtime);
      throw StateError('Explicit runtime initialization approval is required.');
    }
    final adapter = _requireAdapter(id);
    final existing = _states[id];
    if (existing?.lifecycle != RuntimeLifecycle.installed && existing?.lifecycle != RuntimeLifecycle.stopped) throw StateError('Runtime must be installed or stopped before initialization.');
    final reason = compatibilityProblem(adapter.descriptor);
    if (reason != null) return _set(id, RuntimeLifecycle.incompatible, error: reason);
    await _record('initialize-start', id);
    try {
      await adapter.initialize(await _workingDirectory(id));
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
      await _record('initialize-failed', id);
      rethrow;
    }
    return _set(id, RuntimeLifecycle.initialized, version: adapter.descriptor.version);
  }

  Future<RuntimeState> start(String id, {required bool userApproved, required bool policyAllowed}) async {
    await initializeRegistry();
    if (_busy) throw StateError('Another runtime operation is in progress.');
    if (!userApproved || !policyAllowed) {
      DiagnosticReporter.recordGlobal(StateError('Runtime execution was denied by consent or policy.'), category: DiagnosticCategory.runtime);
      throw StateError('Runtime execution requires user approval and policy authorization.');
    }
    final adapter = _requireAdapter(id);
    if (_states[id]?.lifecycle != RuntimeLifecycle.initialized && _states[id]?.lifecycle != RuntimeLifecycle.stopped) {
      throw StateError('Runtime must be initialized before start.');
    }
    if (adapter.descriptor.requiredCapabilities.difference(_grants[id] ?? const <RuntimeCapability>{}).isNotEmpty) {
      throw StateError('Required runtime capabilities are not granted.');
    }
    _busy = true;
    _activeRuntimeId = id;
    late final bool healthy;
    try {
      healthy = await adapter.healthCheck();
    } finally {
      _activeRuntimeId = null;
      _busy = false;
    }
    if (!healthy) return _set(id, RuntimeLifecycle.failed, error: 'Runtime health check failed.');
    return _set(id, RuntimeLifecycle.running, version: adapter.descriptor.version);
  }

  Future<RuntimeState> stop(String id, {required bool userApproved}) async {
    if (_busy) throw StateError('Runtime stop is unavailable while another runtime operation is in progress.');
    _busy = true;
    try {
      await initializeRegistry();
    if (!userApproved) {
      DiagnosticReporter.recordGlobal(StateError('Runtime stop was denied because required consent was not granted.'), category: DiagnosticCategory.runtime);
      throw StateError('Explicit runtime stop approval is required.');
    }
    final adapter = _requireAdapter(id);
    try {
      await adapter.stop();
    } catch (error, stackTrace) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stackTrace, category: DiagnosticCategory.runtime);
      try {
        await _record('runtime-stop-cleanup-failed', id);
      } catch (_) {
        // The persistence failure remains inspectable in persistenceFailures.
      }
      try {
        await _set(id, RuntimeLifecycle.failed, version: adapter.descriptor.version, error: 'Runtime cleanup failed.');
      } catch (stateError, stateStackTrace) {
        DiagnosticReporter.recordGlobal(stateError, stackTrace: stateStackTrace, category: DiagnosticCategory.database);
        _setVolatileCleanupFailure(id, adapter.descriptor.version);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final healthy = await adapter.healthCheck();
    final state = await _set(id, RuntimeLifecycle.stopped, version: adapter.descriptor.version, health: _clock().toUtc());
    if (!healthy) return await _set(id, RuntimeLifecycle.failed, error: 'Runtime health check failed after stop.');
    return state;
    } finally {
      _busy = false;
    }
  }

  Future<RuntimeState> update(String id, String version, {required bool userApproved, required bool licenseAccepted}) async {
    await initializeRegistry();
    if (!userApproved || !licenseAccepted) {
      DiagnosticReporter.recordGlobal(StateError('Runtime update was denied because required consent was not granted.'), category: DiagnosticCategory.runtime);
      throw StateError('Explicit update and license approval are required.');
    }
    if (!RegExp(r'^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$').hasMatch(version)) throw const FormatException('Invalid runtime version.');
    final adapter = _requireAdapter(id);
    final previous = _states[id];
    if (previous == null || previous.lifecycle == RuntimeLifecycle.running) throw StateError('Install the runtime and stop it before updating.');
    final directory = await _workingDirectory(id);
    try {
      await adapter.update(directory, version);
      return await _set(id, RuntimeLifecycle.stopped, version: version);
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
      await _record('update-rollback', id);
      if (previous.installedVersion != null) await adapter.update(directory, previous.installedVersion!);
      rethrow;
    }
  }

  Future<void> uninstall(String id, {required bool userApproved}) async {
    await initializeRegistry();
    if (_busy) throw StateError('Another runtime operation is in progress.');
    if (!userApproved) {
      DiagnosticReporter.recordGlobal(StateError('Runtime uninstall was denied because required consent was not granted.'), category: DiagnosticCategory.runtime);
      throw StateError('Explicit uninstall approval is required.');
    }
    final adapter = _requireAdapter(id);
    if (_states[id]?.lifecycle == RuntimeLifecycle.running) throw StateError('Stop the runtime before uninstalling.');
    final directory = await _workingDirectory(id);
    if (_busy) throw StateError('Another runtime operation is in progress.');
    final previousState = _states[id];
    final previousGrants = _grants[id];
    _busy = true;
    try {
      await _record('uninstall-start', id);
      await adapter.uninstall(directory);
      if (await directory.exists()) await directory.delete(recursive: true);
      _states.remove(id);
      _grants.remove(id);
      await _record('uninstall', id);
      notifyListeners();
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
      if (previousState != null) _states[id] = previousState;
      if (previousGrants != null) _grants[id] = previousGrants;
      try {
        // Uninstall adapters may fail after partial removal. Reinstall is the
        // only adapter-supported compensation and also restores its workspace.
        await adapter.install(directory);
      } catch (compensationError, compensationStack) {
        DiagnosticReporter.recordGlobal(compensationError, stackTrace: compensationStack, category: DiagnosticCategory.runtime);
        _states[id] = RuntimeState(
          id: id,
          lifecycle: RuntimeLifecycle.failed,
          installedVersion: previousState?.installedVersion ?? adapter.descriptor.version,
          updatedAt: _clock().toUtc(),
          lastError: 'Uninstall compensation failed; runtime state is uncertain.',
        );
      }
      notifyListeners();
      try {
        await _record('uninstall-failed', id);
      } catch (auditError, auditStack) {
        DiagnosticReporter.recordGlobal(auditError, stackTrace: auditStack, category: DiagnosticCategory.database);
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      _busy = false;
    }
  }

  Future<RuntimeState> healthCheck(String id) async {
    if (_busy && (_activeRuntimeId == null || _activeRuntimeId == id)) {
      throw StateError('Runtime health check is unavailable while another operation owns this runtime.');
    }
    final adapter = _requireAdapter(id);
    final healthy = await adapter.healthCheck();
    await _record(healthy ? 'health-ok' : 'health-failed', id);
    return _set(id, healthy ? (_states[id]?.lifecycle ?? RuntimeLifecycle.stopped) : RuntimeLifecycle.failed,
        version: adapter.descriptor.version, error: healthy ? null : 'Runtime health check failed.', health: _clock().toUtc());
  }

  Future<T> _awaitTerminalStage<T>(
    _RuntimeTerminalArbiter arbiter,
    Future<T> Function() operation, {
    Duration? timeout,
  }) {
    final terminal = arbiter.outcome;
    if (terminal != null) return Future<T>.error(terminal.asException(), terminal.stackTrace);

    final stage = Completer<T>();
    Timer? deadline;
    if (timeout != null) {
      deadline = _timerFactory(timeout, () => arbiter.trySet(_RuntimeTerminalOutcome.timeout(timeout)));
      arbiter.attachDeadline(deadline);
    }

    Future<T>.sync(operation).then(
      (value) {
        deadline?.cancel();
        if (!arbiter.isSettled && !stage.isCompleted) stage.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        deadline?.cancel();
        arbiter.trySet(_RuntimeTerminalOutcome.failed(error, stackTrace));
      },
    );

    return Future.any<T>([
      stage.future,
      arbiter.future.then<T>((outcome) => throw outcome.asException()),
    ]).whenComplete(() => deadline?.cancel());
  }

  Future<RuntimeExecutionResult> executeTool({
    required String runtimeId,
    required String toolId,
    required Map<String, Object?> input,
    required Set<RuntimeCapability> requiredCapabilities,
    required bool networkAuthorized,
    RuntimeCancellationToken? cancellationToken,
  }) {
    // Admission is synchronous: no await can interleave before the lock is held.
    if (_busy) return Future<RuntimeExecutionResult>.error(const RuntimeExecutionException('Another runtime operation is in progress.'));
    _busy = true;
    final executionId = _newExecutionId();
    _activeExecutionId = executionId;
    _activeRuntimeId = runtimeId;
    _activeToolId = toolId;
    return _executeToolAdmitted(
      executionId: executionId,
      runtimeId: runtimeId,
      toolId: toolId,
      input: input,
      requiredCapabilities: requiredCapabilities,
      networkAuthorized: networkAuthorized,
      cancellationToken: cancellationToken,
    ).then<RuntimeExecutionResult>((result) => result, onError: (Object error, StackTrace stack) {
      if (_executionReports[executionId] == null) {
        final report = RuntimeExecutionReport(
          executionId: executionId,
          runtimeId: runtimeId,
          toolId: toolId,
          outcome: error is RuntimeExecutionCancelled
              ? RuntimeExecutionOutcome.cancelled
              : error is TimeoutException
                  ? RuntimeExecutionOutcome.timeout
                  : RuntimeExecutionOutcome.failed,
          cleanupOutcome: RuntimeCleanupOutcome.notAttempted,
          terminalStateSaveConfirmed: false,
          terminalAuditSaveConfirmed: false,
          persistenceFailures: _persistenceFailures.where((failure) => failure.executionId == executionId).toList(),
        );
        _lastExecutionReport = report;
        _executionReports[executionId] = report;
        while (_executionReports.length > persistenceFailureHistoryLimit) {
          _executionReports.remove(_executionReports.keys.first);
        }
        if (error is RuntimeExecutionCancelled) {
          throw RuntimeExecutionCancelled(report: report);
        }
        if (error is TimeoutException) {
          throw RuntimeExecutionTimeout(error.duration, report);
        }
        if (error is RuntimeExecutionException) {
          throw RuntimeExecutionException(error.message, report: report);
        }
      }
      Error.throwWithStackTrace(error, stack);
    }).whenComplete(() {
      _busy = false;
      _activeExecutionId = null;
      _activeRuntimeId = null;
      _activeToolId = null;
    });
  }

  Future<RuntimeExecutionResult> _executeToolAdmitted({
    required String executionId,
    required String runtimeId,
    required String toolId,
    required Map<String, Object?> input,
    required Set<RuntimeCapability> requiredCapabilities,
    required bool networkAuthorized,
    RuntimeCancellationToken? cancellationToken,
  }) async {
    await initializeRegistry();
    final adapter = _requireAdapter(runtimeId);
    if (adapter is! RuntimeExecutionAdapter || !adapter.descriptor.supportedToolIds.contains(toolId)) {
      await _record('tool-rejected', runtimeId, toolId: toolId);
      DiagnosticReporter.recordGlobal(const RuntimeExecutionException('Tool was rejected by the runtime registry.'), category: DiagnosticCategory.runtime);
      throw const RuntimeExecutionException('No executable adapter is registered for this tool.');
    }
    final descriptor = adapter.descriptor;
    final compatibility = compatibilityProblem(descriptor);
    if (compatibility != null) {
      await _record('tool-rejected-incompatible', runtimeId, toolId: toolId);
      throw RuntimeExecutionException(compatibility);
    }
    final state = _states[runtimeId];
    if (state == null || !{RuntimeLifecycle.installed, RuntimeLifecycle.initialized, RuntimeLifecycle.stopped}.contains(state.lifecycle)) {
      await _record('tool-rejected-not-ready', runtimeId, toolId: toolId);
      throw const RuntimeExecutionException('Runtime is not installed and ready.');
    }
    try {
      _selfProtection.authorizeToolExecution(
        toolId: toolId,
        requestedCapabilities: requiredCapabilities.map((capability) => capability.name).toSet(),
      );
    } on AppSelfProtectionException catch (error, stack) {
      await _record('tool-rejected-self-protection', runtimeId, toolId: toolId);
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
      throw RuntimeExecutionException(error.message);
    }
    if (!descriptor.requiredCapabilities.containsAll(requiredCapabilities) ||
        !(_grants[runtimeId] ?? const <RuntimeCapability>{}).containsAll(requiredCapabilities)) {
      await _record('tool-rejected-capability', runtimeId, toolId: toolId);
      DiagnosticReporter.recordGlobal(const RuntimeExecutionException('Required runtime capability was denied.'), category: DiagnosticCategory.runtime);
      throw const RuntimeExecutionException('Runtime capabilities were not granted.');
    }
    try {
      _policy.authorizeRuntimeTool(
        toolId: toolId,
        networkAuthorized: networkAuthorized,
        requiredCapabilities: requiredCapabilities.map((capability) => capability.name).toSet(),
        grantedCapabilities: (_grants[runtimeId] ?? const <RuntimeCapability>{}).map((capability) => capability.name).toSet(),
      );
    } on PolicyException catch (error, stack) {
      await _record('tool-rejected-policy', runtimeId, toolId: toolId);
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
      rethrow;
    }
    final inputJson = jsonEncode(input);
    if (utf8.encode(inputJson).length > descriptor.resourceLimit.maxInputBytes) {
      await _record('tool-rejected-input', runtimeId, toolId: toolId);
      throw const RuntimeExecutionException('Tool input exceeds the configured size limit.');
    }
    final callerCancellationToken = cancellationToken;
    if (callerCancellationToken?.isCancelled == true) {
      await _record('tool-cancelled-before-start', runtimeId, toolId: toolId);
      throw const RuntimeExecutionCancelled();
    }
    final directory = await _workingDirectory(runtimeId);
    if (callerCancellationToken?.isCancelled == true) {
      await _record('tool-cancelled-before-start', runtimeId, toolId: toolId);
      throw const RuntimeExecutionCancelled();
    }

    final stopwatch = Stopwatch()..start();
    final executionToken = RuntimeCancellationToken();
    final arbiter = _RuntimeTerminalArbiter(executionToken);
    if (callerCancellationToken != null) {
      arbiter.attachCancellationSubscription(
        callerCancellationToken.subscribe(() => arbiter.trySet(const _RuntimeTerminalOutcome.cancelled())),
      );
    }
    _lastExecutionReport = null;
    try {
      late final _RuntimeTerminalOutcome terminal;
      try {
        await _awaitTerminalStage(arbiter, () => _record('tool-start', runtimeId));
        final lifecycle = _states[runtimeId]!.lifecycle;
        if (lifecycle == RuntimeLifecycle.installed || lifecycle == RuntimeLifecycle.stopped) {
          await _awaitTerminalStage(
            arbiter,
            () => adapter.initialize(directory),
            timeout: descriptor.resourceLimit.maxExecution,
          );
          await _awaitTerminalStage(
            arbiter,
            () => _set(runtimeId, RuntimeLifecycle.initialized, version: descriptor.version),
          );
        }
        final healthy = await _awaitTerminalStage(
          arbiter,
          adapter.healthCheck,
          timeout: descriptor.resourceLimit.maxExecution,
        );
        if (!healthy) throw const RuntimeExecutionException('Runtime health check failed before tool execution.');
        await _awaitTerminalStage(
          arbiter,
          () => _set(runtimeId, RuntimeLifecycle.running, version: descriptor.version, health: _clock().toUtc()),
        );

        if (arbiter.isSettled) throw arbiter.outcome!.asException();
        // Adapters receive only the child token. The arbiter owns the caller
        // subscription and fixes the winning cause before cleanup begins.
        final request = RuntimeToolRequest(
          toolId: toolId,
          input: Map<String, Object?>.unmodifiable(input),
          requiredCapabilities: Set.unmodifiable(requiredCapabilities),
          networkAuthorized: networkAuthorized,
          cancellationToken: executionToken,
        );
        final executionDeadline = descriptor.resourceLimit.maxExecution;
        final deadline = _timerFactory(
          executionDeadline,
          () => arbiter.trySet(_RuntimeTerminalOutcome.timeout(executionDeadline)),
        );
        arbiter.attachDeadline(deadline);
        Future<Map<String, Object?>>.sync(() => adapter.executeTool(request)).then(
          (output) {
            deadline.cancel();
            try {
              if (output.keys.any((key) => key.isEmpty || key.length > 100)) {
                throw const RuntimeExecutionException('Runtime returned invalid output keys.');
              }
              final encodedOutput = jsonEncode(output);
              if (utf8.encode(encodedOutput).length > descriptor.resourceLimit.maxOutputBytes) {
                throw const RuntimeExecutionException('Runtime output exceeds the configured size limit.');
              }
              final safeOutput = Map<String, Object?>.unmodifiable(
                Map<String, Object?>.from(jsonDecode(encodedOutput) as Map<String, dynamic>),
              );
              arbiter.trySet(_RuntimeTerminalOutcome.success(safeOutput));
            } catch (error, stackTrace) {
              arbiter.trySet(_RuntimeTerminalOutcome.failed(error, stackTrace));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            deadline.cancel();
            if (error is TimeoutException) {
              arbiter.trySet(_RuntimeTerminalOutcome.timeout(error.duration ?? executionDeadline));
            } else {
              arbiter.trySet(_RuntimeTerminalOutcome.failed(error, stackTrace));
            }
          },
        );
        terminal = await arbiter.future;
      } catch (error, stackTrace) {
        final proposed = error is RuntimeExecutionCancelled
            ? const _RuntimeTerminalOutcome.cancelled()
            : error is TimeoutException
                ? _RuntimeTerminalOutcome.timeout(error.duration ?? descriptor.resourceLimit.maxExecution)
                : _RuntimeTerminalOutcome.failed(error, stackTrace);
        arbiter.trySet(proposed);
        terminal = arbiter.outcome!;
      }

      // The outcome and caller subscription are fixed before cleanup awaits.
      Object? cleanupError;
      try {
        await adapter.stop();
      } catch (error, stackTrace) {
        cleanupError = error;
        DiagnosticReporter.recordGlobal(error, stackTrace: stackTrace, category: DiagnosticCategory.runtime);
        try {
          await _record('tool-cleanup-failed', runtimeId, toolId: toolId);
        } catch (_) {
          // The report below records that cleanup/audit persistence is unconfirmed.
        }
      }

      var terminalStateSaveConfirmed = false;
      var terminalAuditSaveConfirmed = false;
      if (terminal.kind == _RuntimeTerminalKind.success) {
        try {
          await _set(
            runtimeId,
            cleanupError == null ? RuntimeLifecycle.stopped : RuntimeLifecycle.failed,
            version: descriptor.version,
            error: cleanupError == null ? null : 'Runtime cleanup failed.',
            health: _clock().toUtc(),
          );
          terminalStateSaveConfirmed = true;
        } catch (error, stackTrace) {
          DiagnosticReporter.recordGlobal(error, stackTrace: stackTrace, category: DiagnosticCategory.database);
          if (cleanupError != null) _setVolatileCleanupFailure(runtimeId, descriptor.version);
        }
        try {
          await _record('tool-complete', runtimeId, toolId: toolId);
          terminalAuditSaveConfirmed = true;
        } catch (error, stackTrace) {
          DiagnosticReporter.recordGlobal(error, stackTrace: stackTrace, category: DiagnosticCategory.database);
        }
      } else {
        final detail = switch (terminal.kind) {
          _RuntimeTerminalKind.cancelled => 'cancelled',
          _RuntimeTerminalKind.timeout => 'timeout',
          _RuntimeTerminalKind.failed => terminal.error is RuntimeExecutionException &&
                  (terminal.error! as RuntimeExecutionException).message.contains('output')
              ? 'invalid-output'
              : sanitizeDiagnosticText(terminal.error!.runtimeType.toString()),
          _RuntimeTerminalKind.success => throw StateError('Unexpected successful terminal outcome.'),
        };
        try {
          await _record('tool-$detail', runtimeId, toolId: toolId);
          terminalAuditSaveConfirmed = true;
        } catch (error, stackTrace) {
          DiagnosticReporter.recordGlobal(error, stackTrace: stackTrace, category: DiagnosticCategory.database);
        }
        final healthyAfterCleanup = cleanupError == null && await adapter.healthCheck().catchError((_) => false);
        try {
          await _set(
            runtimeId,
            healthyAfterCleanup ? RuntimeLifecycle.stopped : RuntimeLifecycle.failed,
            version: descriptor.version,
            error: cleanupError == null ? sanitizeDiagnosticText(detail) : 'Runtime cleanup failed after $detail outcome.',
            health: _clock().toUtc(),
          );
          terminalStateSaveConfirmed = true;
        } catch (error, stackTrace) {
          DiagnosticReporter.recordGlobal(error, stackTrace: stackTrace, category: DiagnosticCategory.database);
          if (cleanupError != null) _setVolatileCleanupFailure(runtimeId, descriptor.version);
        }
      }

      final report = RuntimeExecutionReport(
        executionId: executionId,
        runtimeId: runtimeId,
        toolId: toolId,
        outcome: switch (terminal.kind) {
          _RuntimeTerminalKind.success => RuntimeExecutionOutcome.success,
          _RuntimeTerminalKind.failed => RuntimeExecutionOutcome.failed,
          _RuntimeTerminalKind.timeout => RuntimeExecutionOutcome.timeout,
          _RuntimeTerminalKind.cancelled => RuntimeExecutionOutcome.cancelled,
        },
        cleanupOutcome: cleanupError == null ? RuntimeCleanupOutcome.succeeded : RuntimeCleanupOutcome.failed,
        cleanupErrorType: cleanupError == null ? null : sanitizeDiagnosticText(cleanupError.runtimeType.toString()),
        terminalStateSaveConfirmed: terminalStateSaveConfirmed,
        terminalAuditSaveConfirmed: terminalAuditSaveConfirmed,
        persistenceFailures: _persistenceFailures.where((failure) => failure.executionId == executionId).toList(),
      );
      _lastExecutionReport = report;
      _executionReports[executionId] = report;
      while (_executionReports.length > persistenceFailureHistoryLimit) {
        _executionReports.remove(_executionReports.keys.first);
      }

      if (terminal.kind == _RuntimeTerminalKind.success) {
        return RuntimeExecutionResult(
          runtimeId: runtimeId,
          toolId: toolId,
          output: terminal.output!,
          duration: stopwatch.elapsed,
          report: report,
        );
      }
      switch (terminal.kind) {
        case _RuntimeTerminalKind.cancelled:
          throw RuntimeExecutionCancelled(report: report);
        case _RuntimeTerminalKind.timeout:
          throw RuntimeExecutionTimeout(terminal.timeout, report);
        case _RuntimeTerminalKind.failed:
          final message = terminal.error is RuntimeExecutionException
              ? (terminal.error! as RuntimeExecutionException).message
              : sanitizeDiagnosticText(terminal.error.toString());
          throw RuntimeExecutionException(message, report: report);
        case _RuntimeTerminalKind.success:
          throw StateError('Unexpected successful terminal outcome.');
      }
    } finally {
      arbiter._cancellationSubscription?.dispose();
      arbiter._deadline?.cancel();
    }
  }

  RuntimeAdapter _requireAdapter(String id) {
    final adapter = _adapters[id];
    if (adapter != null) return adapter;
    final error = StateError('No approved runtime adapter is registered.');
    DiagnosticReporter.recordGlobal(error, category: DiagnosticCategory.runtime);
    throw error;
  }
  Future<Directory> _workingDirectory(String id) async {
    if (!RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(id)) throw const FormatException('Invalid runtime ID.');
    final root = await _supportDirectoryProvider();
    final directory = Directory(p.join(root.path, 'runtime_workspaces', id));
    await directory.create(recursive: true);
    return directory;
  }

  Future<RuntimeState> _withLifecycle(String id, RuntimeLifecycle failure, Future<RuntimeState> Function() task) async {
    if (_busy) throw StateError('Another runtime lifecycle operation is in progress.');
    _busy = true;
    try {
      return await task();
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
      try {
        await _set(id, failure, error: sanitizeDiagnosticText(error.runtimeType.toString()));
      } catch (stateError, stateStack) {
        DiagnosticReporter.recordGlobal(stateError, stackTrace: stateStack, category: DiagnosticCategory.database);
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      _busy = false;
    }
  }

  void _setVolatileCleanupFailure(String id, String version) {
    final prior = _states[id];
    _states[id] = RuntimeState(
      id: id,
      lifecycle: RuntimeLifecycle.failed,
      installedVersion: version,
      updatedAt: _clock().toUtc(),
      lastHealthCheck: prior?.lastHealthCheck,
      lastError: 'Runtime cleanup failed; state persistence is unconfirmed.',
    );
    notifyListeners();
  }

  Future<RuntimeState> _set(String id, RuntimeLifecycle lifecycle, {String? version, String? error, DateTime? health}) async {
    final prior = _states[id];
    final next = RuntimeState(id: id, lifecycle: lifecycle, installedVersion: version ?? prior?.installedVersion,
        updatedAt: _clock().toUtc(), lastHealthCheck: health ?? prior?.lastHealthCheck, lastError: error);
    _states[id] = next;
    try {
      await _record(lifecycle.name, id);
    } catch (error) {
      if (prior == null) {
        _states.remove(id);
      } else {
        _states[id] = prior;
      }
      _rememberPersistenceFailure(RuntimePersistenceKind.state, lifecycle.name, error);
      rethrow;
    }
    notifyListeners();
    return next;
  }

  Future<void> _record(String action, String id, {String? toolId}) async {
    final at = _clock().toUtc();
    final event = <String, Object?>{
      'eventId': 'runtime-${at.microsecondsSinceEpoch}-${++_auditSequence}',
      'at': at.toIso8601String(),
      'action': sanitizeDiagnosticText(action),
      'runtimeId': sanitizeDiagnosticText(id),
      if (_activeExecutionId != null && !_registryMutation) 'executionId': _activeExecutionId,
      if (toolId != null) 'toolId': sanitizeDiagnosticText(toolId),
    };
    _audit.insert(0, event);
    try {
      await _persist();
    } catch (error) {
      _audit.remove(event);
      _rememberPersistenceFailure(RuntimePersistenceKind.audit, action, error);
      rethrow;
    }
  }

  void _rememberPersistenceFailure(
    RuntimePersistenceKind kind,
    String operation,
    Object error, {
    String? executionId,
    String? runtimeId,
    String? toolId,
  }) {
    final failureKind = _registryMutation ? RuntimePersistenceKind.registry : kind;
    _persistenceFailures.add(RuntimePersistenceFailure(
      sequence: ++_persistenceFailureSequence,
      kind: failureKind,
      operation: sanitizeDiagnosticText(operation),
      errorType: sanitizeDiagnosticText(error.runtimeType.toString()),
      at: _clock().toUtc(),
      executionId: executionId ?? (failureKind == RuntimePersistenceKind.registry ? null : _activeExecutionId),
      runtimeId: runtimeId ?? (failureKind == RuntimePersistenceKind.registry ? null : _activeRuntimeId),
      toolId: toolId ?? (failureKind == RuntimePersistenceKind.registry ? null : _activeToolId),
    ));
    if (_persistenceFailures.length > persistenceFailureHistoryLimit) _persistenceFailures.removeAt(0);
  }

  Future<void> _persist() async {
    try {
      await store.save({
        'states': _states.values.map((state) => state.toJson()).toList(),
        'grants': _grants.map((id, capabilities) => MapEntry(id, capabilities.map((capability) => capability.name).toList())),
        'audit': _audit,
      });
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      rethrow;
    }
  }
}
