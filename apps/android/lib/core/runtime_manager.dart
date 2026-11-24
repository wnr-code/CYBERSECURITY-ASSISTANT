import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostics.dart';
import 'policy_engine.dart';

enum RuntimeLifecycle { available, installed, initialized, running, stopped, failed, incompatible }
enum RuntimeCapability { filesystemRead, filesystemWrite, network, processExecution, nativeCode }

class RuntimeDescriptor {
  const RuntimeDescriptor({
    required this.id,
    required this.name,
    required this.version,
    required this.license,
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
  final String license;
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
      version.isNotEmpty && license.trim().isNotEmpty &&
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

class RuntimeCancellationToken {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
  void throwIfCancelled() {
    if (isCancelled) throw const RuntimeExecutionCancelled();
  }
}

class RuntimeExecutionCancelled implements Exception {
  const RuntimeExecutionCancelled();
  @override
  String toString() => 'Runtime execution was cancelled.';
}

class RuntimeExecutionException implements Exception {
  const RuntimeExecutionException(this.message);
  final String message;
  @override
  String toString() => message;
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

class RuntimeExecutionResult {
  const RuntimeExecutionResult({required this.runtimeId, required this.toolId, required this.output, required this.duration});
  final String runtimeId;
  final String toolId;
  final Map<String, Object?> output;
  final Duration duration;
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
  })  : _clock = clock ?? DateTime.now,
        _policy = policy ?? PolicyEngine(),
        _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory {
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
  final DateTime Function() _clock;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Map<String, RuntimeAdapter> _adapters = {};
  final Map<String, RuntimeState> _states = {};
  final Map<String, Set<RuntimeCapability>> _grants = {};
  final List<Map<String, Object?>> _audit = [];
  bool _initialized = false;
  Future<void>? _initialization;
  bool _busy = false;
  List<RuntimeState> get states => List.unmodifiable(_states.values);
  List<Map<String, Object?>> get auditEvents => List.unmodifiable(_audit.map((entry) => Map<String, Object?>.unmodifiable(entry)));
  List<RuntimeDescriptor> get registered => List.unmodifiable(_adapters.values.map((adapter) => adapter.descriptor));
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
    final snapshot = await store.load();
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
      for (final item in audit.whereType<Map<String, dynamic>>().take(100)) {
        _audit.add(Map<String, Object?>.from(item));
      }
    }
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
      } catch (error) {
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
    _initialized = true;
    await _persist();
    notifyListeners();
  }

  Future<RuntimeState> install(String id, {required bool userApproved, required bool licenseAccepted, Set<RuntimeCapability> grantedCapabilities = const {}}) async {
    await initializeRegistry();
    final adapter = _requireAdapter(id);
    final descriptor = adapter.descriptor;
    if (!userApproved || !licenseAccepted) throw StateError('Explicit install and license approval are required.');
    final reason = compatibilityProblem(descriptor);
    if (reason != null) return _set(id, RuntimeLifecycle.incompatible, error: reason);
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
    return _withLifecycle(id, RuntimeLifecycle.installed, () async {
      await adapter.install(directory);
      _grants[id] = Set.unmodifiable(grantedCapabilities);
      return _set(id, RuntimeLifecycle.installed, version: descriptor.version);
    });
  }

  Future<RuntimeState> initializeRuntime(String id, {required bool userApproved}) async {
    await initializeRegistry();
    if (!userApproved) throw StateError('Explicit runtime initialization approval is required.');
    final adapter = _requireAdapter(id);
    final existing = _states[id];
    if (existing?.lifecycle != RuntimeLifecycle.installed && existing?.lifecycle != RuntimeLifecycle.stopped) throw StateError('Runtime must be installed or stopped before initialization.');
    final reason = compatibilityProblem(adapter.descriptor);
    if (reason != null) return _set(id, RuntimeLifecycle.incompatible, error: reason);
    await adapter.initialize(await _workingDirectory(id));
    return _set(id, RuntimeLifecycle.initialized, version: adapter.descriptor.version);
  }

  Future<RuntimeState> start(String id, {required bool userApproved, required bool policyAllowed}) async {
    await initializeRegistry();
    if (!userApproved || !policyAllowed) throw StateError('Runtime execution requires user approval and policy authorization.');
    final adapter = _requireAdapter(id);
    if (_states[id]?.lifecycle != RuntimeLifecycle.initialized && _states[id]?.lifecycle != RuntimeLifecycle.stopped) throw StateError('Runtime must be initialized before start.');
    if (adapter.descriptor.requiredCapabilities.difference(_grants[id] ?? const <RuntimeCapability>{}).isNotEmpty) throw StateError('Required runtime capabilities are not granted.');
    if (!await adapter.healthCheck()) return _set(id, RuntimeLifecycle.failed, error: 'Runtime health check failed.');
    return _set(id, RuntimeLifecycle.running, version: adapter.descriptor.version);
  }

  Future<RuntimeState> stop(String id, {required bool userApproved}) async {
    await initializeRegistry();
    if (!userApproved) throw StateError('Explicit runtime stop approval is required.');
    final adapter = _requireAdapter(id);
    await adapter.stop();
    final healthy = await adapter.healthCheck();
    final state = await _set(id, RuntimeLifecycle.stopped, version: adapter.descriptor.version, health: _clock().toUtc());
    if (!healthy) return _set(id, RuntimeLifecycle.failed, error: 'Runtime health check failed after stop.');
    return state;
  }

  Future<RuntimeState> update(String id, String version, {required bool userApproved, required bool licenseAccepted}) async {
    await initializeRegistry();
    if (!userApproved || !licenseAccepted) throw StateError('Explicit update and license approval are required.');
    if (!RegExp(r'^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$').hasMatch(version)) throw const FormatException('Invalid runtime version.');
    final adapter = _requireAdapter(id);
    final previous = _states[id];
    if (previous == null || previous.lifecycle == RuntimeLifecycle.running) throw StateError('Install the runtime and stop it before updating.');
    final directory = await _workingDirectory(id);
    try {
      await adapter.update(directory, version);
      return await _set(id, RuntimeLifecycle.stopped, version: version);
    } catch (error) {
      await _record('update-rollback', id);
      if (previous.installedVersion != null) await adapter.update(directory, previous.installedVersion!);
      rethrow;
    }
  }

  Future<void> uninstall(String id, {required bool userApproved}) async {
    await initializeRegistry();
    if (!userApproved) throw StateError('Explicit uninstall approval is required.');
    final adapter = _requireAdapter(id);
    if (_states[id]?.lifecycle == RuntimeLifecycle.running) throw StateError('Stop the runtime before uninstalling.');
    final directory = await _workingDirectory(id);
    await adapter.uninstall(directory);
    if (await directory.exists()) await directory.delete(recursive: true);
    _states.remove(id);
    _grants.remove(id);
    await _record('uninstall', id);
    await _persist();
    notifyListeners();
  }

  Future<RuntimeState> healthCheck(String id) async {
    final adapter = _requireAdapter(id);
    final healthy = await adapter.healthCheck();
    await _record(healthy ? 'health-ok' : 'health-failed', id);
    return _set(id, healthy ? (_states[id]?.lifecycle ?? RuntimeLifecycle.stopped) : RuntimeLifecycle.failed,
        version: adapter.descriptor.version, error: healthy ? null : 'Runtime health check failed.', health: _clock().toUtc());
  }

  Future<RuntimeExecutionResult> executeTool({
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
      throw const RuntimeExecutionException('No executable adapter is registered for this tool.');
    }
    if (_busy) {
      await _record('tool-rejected-busy', runtimeId, toolId: toolId);
      throw const RuntimeExecutionException('Another runtime execution is in progress.');
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
    if (!descriptor.requiredCapabilities.containsAll(requiredCapabilities) ||
        !(_grants[runtimeId] ?? const <RuntimeCapability>{}).containsAll(requiredCapabilities)) {
      await _record('tool-rejected-capability', runtimeId, toolId: toolId);
      throw const RuntimeExecutionException('Runtime capabilities were not granted.');
    }
    try {
      _policy.authorizeRuntimeTool(
        toolId: toolId,
        networkAuthorized: networkAuthorized,
        requiredCapabilities: requiredCapabilities.map((capability) => capability.name).toSet(),
        grantedCapabilities: (_grants[runtimeId] ?? const <RuntimeCapability>{}).map((capability) => capability.name).toSet(),
      );
    } on PolicyException {
      await _record('tool-rejected-policy', runtimeId, toolId: toolId);
      rethrow;
    }
    final inputJson = jsonEncode(input);
    if (utf8.encode(inputJson).length > descriptor.resourceLimit.maxInputBytes) {
      await _record('tool-rejected-input', runtimeId, toolId: toolId);
      throw const RuntimeExecutionException('Tool input exceeds the configured size limit.');
    }
    final token = cancellationToken ?? RuntimeCancellationToken();
    if (token.isCancelled) {
      await _record('tool-cancelled-before-start', runtimeId, toolId: toolId);
      token.throwIfCancelled();
    }
    final directory = await _workingDirectory(runtimeId);
    final stopwatch = Stopwatch()..start();
    _busy = true;
    try {
      await _record('tool-start', runtimeId, toolId: toolId);
      final lifecycle = _states[runtimeId]!.lifecycle;
      if (lifecycle == RuntimeLifecycle.installed || lifecycle == RuntimeLifecycle.stopped) {
        await adapter.initialize(directory).timeout(descriptor.resourceLimit.maxExecution);
        await _set(runtimeId, RuntimeLifecycle.initialized, version: descriptor.version);
      }
      token.throwIfCancelled();
      if (!await adapter.healthCheck().timeout(descriptor.resourceLimit.maxExecution)) {
        throw const RuntimeExecutionException('Runtime health check failed before tool execution.');
      }
      await _set(runtimeId, RuntimeLifecycle.running, version: descriptor.version, health: _clock().toUtc());
      final request = RuntimeToolRequest(
        toolId: toolId,
        input: Map<String, Object?>.unmodifiable(input),
        requiredCapabilities: Set.unmodifiable(requiredCapabilities),
        networkAuthorized: networkAuthorized,
        cancellationToken: token,
      );
      final execution = adapter.executeTool(request).timeout(descriptor.resourceLimit.maxExecution);
      final output = await Future.any<Map<String, Object?>>([
        execution,
        token.whenCancelled.then((_) => throw const RuntimeExecutionCancelled()),
      ]);
      token.throwIfCancelled();
      if (output.keys.any((key) => key.isEmpty || key.length > 100)) {
        throw const RuntimeExecutionException('Tool returned invalid output keys.');
      }
      final encodedOutput = jsonEncode(output);
      if (utf8.encode(encodedOutput).length > descriptor.resourceLimit.maxOutputBytes) {
        throw const RuntimeExecutionException('Tool output exceeds the configured size limit.');
      }
      await adapter.stop();
      await _set(runtimeId, RuntimeLifecycle.stopped, version: descriptor.version, health: _clock().toUtc());
      await _record('tool-complete', runtimeId, toolId: toolId);
      return RuntimeExecutionResult(
        runtimeId: runtimeId,
        toolId: toolId,
        output: Map<String, Object?>.unmodifiable(Map<String, Object?>.from(jsonDecode(encodedOutput) as Map<String, dynamic>)),
        duration: stopwatch.elapsed,
      );
    } catch (error, stack) {
      token.cancel();
      try {
        await adapter.stop();
      } catch (_) {
        // Cleanup is best-effort after timeout/cancellation; never mask the failure.
      }
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
      final isCancellation = error is RuntimeExecutionCancelled;
      final isTimeout = error is TimeoutException;
      final isInvalidOutput = error is RuntimeExecutionException && error.message.contains('output');
      final detail = isCancellation ? 'cancelled' : isTimeout ? 'timeout' : isInvalidOutput ? 'invalid-output' : sanitizeDiagnosticText(error.runtimeType.toString());
      await _record('tool-$detail', runtimeId, toolId: toolId);
      final healthy = await adapter.healthCheck().catchError((_) => false);
      await _set(runtimeId, healthy ? RuntimeLifecycle.stopped : RuntimeLifecycle.failed,
          version: descriptor.version, error: sanitizeDiagnosticText(detail), health: _clock().toUtc());
      if (error is RuntimeExecutionException || error is RuntimeExecutionCancelled || error is TimeoutException) rethrow;
      throw RuntimeExecutionException(sanitizeDiagnosticText(error.toString()));
    } finally {
      _busy = false;
    }
  }

  RuntimeAdapter _requireAdapter(String id) => _adapters[id] ?? (throw StateError('No approved runtime adapter is registered for $id.'));
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
      return _set(id, failure, error: sanitizeDiagnosticText(error.runtimeType.toString()));
    } finally {
      _busy = false;
    }
  }

  Future<RuntimeState> _set(String id, RuntimeLifecycle lifecycle, {String? version, String? error, DateTime? health}) async {
    final prior = _states[id];
    final next = RuntimeState(id: id, lifecycle: lifecycle, installedVersion: version ?? prior?.installedVersion,
        updatedAt: _clock().toUtc(), lastHealthCheck: health ?? prior?.lastHealthCheck, lastError: error);
    _states[id] = next;
    await _record(lifecycle.name, id);
    await _persist();
    notifyListeners();
    return next;
  }

  Future<void> _record(String action, String id, {String? toolId}) async {
    _audit.insert(0, {
      'at': _clock().toUtc().toIso8601String(),
      'action': sanitizeDiagnosticText(action),
      'runtimeId': sanitizeDiagnosticText(id),
      if (toolId != null) 'toolId': sanitizeDiagnosticText(toolId),
    });
    if (_audit.length > 100) _audit.removeRange(100, _audit.length);
  }

  Future<void> _persist() => store.save({
        'states': _states.values.map((state) => state.toJson()).toList(),
        'grants': _grants.map((id, capabilities) => MapEntry(id, capabilities.map((capability) => capability.name).toList())),
        'audit': _audit,
      });
}
