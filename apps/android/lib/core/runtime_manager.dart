import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'diagnostics.dart';

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

  bool get metadataValid => RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(id) &&
      version.isNotEmpty && license.trim().isNotEmpty &&
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256) && officialSource.isNotEmpty;
}

/// Declared adapter budgets are validated, but cannot enforce OS process/memory quotas without a concrete sandboxed runtime.
class RuntimeResourceLimit {
  const RuntimeResourceLimit({this.maxMemoryMb = 64, this.maxExecution = const Duration(seconds: 10), this.maxOutputBytes = 65536});
  final int maxMemoryMb;
  final Duration maxExecution;
  final int maxOutputBytes;
  bool get valid => maxMemoryMb > 0 && maxMemoryMb <= 512 && maxExecution > Duration.zero && maxExecution <= const Duration(minutes: 2) && maxOutputBytes > 0 && maxOutputBytes <= 1048576;
}

class RuntimeEnvironment {
  const RuntimeEnvironment({required this.platform, required this.abi, this.availableCapabilities = const {RuntimeCapability.filesystemRead, RuntimeCapability.filesystemWrite}});
  final String platform;
  final String? abi;
  final Set<RuntimeCapability> availableCapabilities;
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
  RuntimeManager({required this.environment, required this.store, Iterable<RuntimeAdapter> adapters = const [], DateTime Function()? clock, Future<Directory> Function()? supportDirectoryProvider})
      : _clock = clock ?? DateTime.now,
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
  final DateTime Function() _clock;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Map<String, RuntimeAdapter> _adapters = {};
  final Map<String, RuntimeState> _states = {};
  final Map<String, Set<RuntimeCapability>> _grants = {};
  final List<Map<String, Object?>> _audit = [];
  bool _initialized = false;
  bool _busy = false;
  List<RuntimeState> get states => List.unmodifiable(_states.values);
  List<Map<String, Object?>> get auditEvents => List.unmodifiable(_audit.map((entry) => Map<String, Object?>.unmodifiable(entry)));
  List<RuntimeDescriptor> get registered => List.unmodifiable(_adapters.values.map((adapter) => adapter.descriptor));
  bool get busy => _busy;

  String? compatibilityProblem(RuntimeDescriptor descriptor) {
    if (!descriptor.metadataValid || !descriptor.resourceLimit.valid) return 'Runtime metadata or resource limits are invalid.';
    if (!descriptor.supportedPlatforms.any((platform) => platform.toLowerCase() == environment.platform.toLowerCase() || platform == 'Any')) return 'Runtime does not support this platform.';
    final abi = environment.abi;
    if (descriptor.supportedAbis.isNotEmpty && (abi == null || !descriptor.supportedAbis.contains(abi))) return 'Runtime is not confirmed compatible with this device ABI.';
    final missing = descriptor.requiredCapabilities.difference(environment.availableCapabilities);
    if (missing.isNotEmpty) return 'Missing capabilities: ${missing.map((item) => item.name).join(', ')}.';
    return null;
  }

  RuntimeState? stateFor(String id) => _states[id];

  Future<void> initializeRegistry() async {
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
    _initialized = true;
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

  Future<void> _record(String action, String id) async {
    _audit.insert(0, {'at': _clock().toUtc().toIso8601String(), 'action': sanitizeDiagnosticText(action), 'runtimeId': sanitizeDiagnosticText(id)});
    if (_audit.length > 100) _audit.removeRange(100, _audit.length);
  }

  Future<void> _persist() => store.save({
        'states': _states.values.map((state) => state.toJson()).toList(),
        'grants': _grants.map((id, capabilities) => MapEntry(id, capabilities.map((capability) => capability.name).toList())),
        'audit': _audit,
      });
}
