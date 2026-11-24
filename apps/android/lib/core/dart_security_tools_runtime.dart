import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'runtime_manager.dart';
import 'security_tools.dart';
import 'tool_result_codec.dart';

/// Executes only first-party, statically registered Dart tools already compiled
/// into the app. This is not a shell, ELF loader, plugin loader, or Market runner.
class DartSecurityToolsRuntime implements RuntimeExecutionAdapter {
  DartSecurityToolsRuntime({SecurityTools? tools}) : _tools = tools ?? SecurityTools();

  static const runtimeId = 'runtime.dart.security-tools';
  static const runtimeVersion = '1.0.0';
  static const _manifestFile = 'runtime-manifest.json';
  // SHA-256 of `bundled-dart-adapter|runtime.dart.security-tools|1.0.0|dns_lookup,tls_inspector,http_headers,response_analyzer`;
  // this is an identity fingerprint, not a binary signature or source-code hash.
  static const _sha256 = 'e9bdfb1228eb9b19350143b0707eedee104a3d3d8ed5238bebe0b7084b52f2bd';
  static const _toolIds = <String>{'dns_lookup', 'tls_inspector', 'http_headers', 'response_analyzer'};

  final SecurityTools _tools;
  Directory? _workspace;
  bool _initialized = false;

  @override
  RuntimeDescriptor get descriptor => const RuntimeDescriptor(
        id: runtimeId,
        name: 'Bundled Dart Security Tools',
        version: runtimeVersion,
        license: 'Cybersecurity Assistant application license',
        supportedPlatforms: ['Android', 'Linux'],
        supportedAbis: ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
        minAndroidApi: 21,
        dependencies: [],
        requiredCapabilities: {RuntimeCapability.network},
        supportedToolIds: ['dns_lookup', 'tls_inspector', 'http_headers', 'response_analyzer'],
        sha256: _sha256,
        officialSource: 'Dart implementation bundled in the Cybersecurity Assistant APK; no external binary',
        resourceLimit: RuntimeResourceLimit(
          maxMemoryMb: 64,
          maxExecution: Duration(seconds: 10),
          maxInputBytes: 65536,
          maxOutputBytes: 65536,
        ),
        bundled: true,
      );

  @override
  Future<void> install(Directory isolatedWorkingDirectory) async {
    await isolatedWorkingDirectory.create(recursive: true);
    final manifest = File(p.join(isolatedWorkingDirectory.path, _manifestFile));
    await manifest.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'runtimeId': runtimeId,
      'runtimeVersion': runtimeVersion,
      'sha256': _sha256,
      'implementation': 'bundled-dart',
    }), flush: true);
    _workspace = isolatedWorkingDirectory;
  }

  @override
  Future<void> initialize(Directory isolatedWorkingDirectory) async {
    final manifest = File(p.join(isolatedWorkingDirectory.path, _manifestFile));
    if (!await manifest.exists()) throw const FormatException('Bundled Dart runtime is not installed.');
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != 1 ||
        decoded['runtimeId'] != runtimeId ||
        decoded['runtimeVersion'] != runtimeVersion ||
        decoded['sha256'] != _sha256 ||
        decoded['implementation'] != 'bundled-dart') {
      throw const FormatException('Bundled Dart runtime manifest is invalid.');
    }
    _workspace = isolatedWorkingDirectory;
    _initialized = true;
  }

  @override
  Future<void> stop() async {
    _initialized = false;
  }

  @override
  Future<void> update(Directory isolatedWorkingDirectory, String version) async {
    if (version != runtimeVersion) throw UnsupportedError('The bundled runtime is updated with the application, not from Market.');
    await install(isolatedWorkingDirectory);
  }

  @override
  Future<void> uninstall(Directory isolatedWorkingDirectory) async {
    final manifest = File(p.join(isolatedWorkingDirectory.path, _manifestFile));
    if (await manifest.exists()) await manifest.delete();
    _workspace = null;
    _initialized = false;
  }

  @override
  Future<bool> healthCheck() async {
    final workspace = _workspace;
    if (workspace == null) return false;
    final manifest = File(p.join(workspace.path, _manifestFile));
    if (!await manifest.exists()) return false;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      return decoded is Map<String, dynamic> &&
          decoded['runtimeId'] == runtimeId &&
          decoded['runtimeVersion'] == runtimeVersion &&
          decoded['sha256'] == _sha256;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, Object?>> executeTool(RuntimeToolRequest request) async {
    if (!_initialized || !_toolIds.contains(request.toolId)) {
      throw const RuntimeExecutionException('Runtime is not initialized for this registered tool.');
    }
    request.cancellationToken.throwIfCancelled();
    final input = request.input;
    final Future<ToolRunResult> operation;
    switch (request.toolId) {
      case 'dns_lookup':
        _requireKeys(input, const {'target'});
        operation = _tools.runDnsLookup(_requireTarget(input), authorized: request.networkAuthorized);
        break;
      case 'tls_inspector':
        _requireKeys(input, const {'target', 'allowPrivateNetwork'});
        operation = _tools.inspectTls(
          _requireTarget(input),
          authorized: request.networkAuthorized,
          allowPrivateNetwork: _optionalBool(input, 'allowPrivateNetwork'),
        );
        break;
      case 'http_headers':
        _requireKeys(input, const {'target', 'allowPrivateNetwork'});
        operation = _tools.checkHttpHeaders(
          _requireTarget(input),
          authorized: request.networkAuthorized,
          allowPrivateNetwork: _optionalBool(input, 'allowPrivateNetwork'),
        );
        break;
      case 'response_analyzer':
        _requireKeys(input, const {'target', 'priorResults'});
        if (request.requiredCapabilities.isNotEmpty) throw const RuntimeExecutionException('Local analysis must not request network capabilities.');
        final targetValue = input['target'];
        final rawResults = input['priorResults'];
        if (targetValue is! String || targetValue.length > 2048 || rawResults is! List || rawResults.isEmpty || rawResults.length > 16 || rawResults.any((value) => value is! String)) {
          throw const FormatException('Analysis input is invalid.');
        }
        final results = rawResults.cast<String>().map(decodeToolRunResult).where((result) => result.toolId != 'response_analyzer').toList(growable: false);
        if (results.isEmpty) throw const FormatException('Run and save at least one local check before analysis.');
        final target = targetValue.isEmpty ? results.first.target : targetValue;
        final scopedResults = results.where((result) => result.target == target).toList(growable: false);
        if (scopedResults.isEmpty) throw const FormatException('No saved results match the requested target.');
        operation = Future<ToolRunResult>.sync(() => _tools.analyze(scopedResults, target: target));
        break;
      default:
        throw const RuntimeExecutionException('Tool is not allowlisted by the bundled runtime.');
    }
    final result = await Future.any<ToolRunResult>([
      operation,
      request.cancellationToken.whenCancelled.then((_) => throw const RuntimeExecutionCancelled()),
    ]);
    request.cancellationToken.throwIfCancelled();
    if (result.toolId != request.toolId || result.target.length > 2048 || result.details.length > 128 || result.findings.length > 128) {
      throw const FormatException('Tool returned an invalid result shape.');
    }
    final encoded = encodeToolRunResult(result);
    if (utf8.encode(encoded).length > descriptor.resourceLimit.maxOutputBytes) {
      throw const RuntimeExecutionException('Tool result exceeded the runtime output limit.');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Tool result is not a JSON object.');
    return Map<String, Object?>.from(decoded);
  }

  static String _requireTarget(Map<String, Object?> input) {
    final target = input['target'];
    if (target is! String || target.trim().isEmpty || target.length > 2048) {
      throw const FormatException('Tool target is missing or exceeds the input limit.');
    }
    return target;
  }

  static bool _optionalBool(Map<String, Object?> input, String key) {
    final value = input[key];
    if (value == null) return false;
    if (value is! bool) throw FormatException('Input field "$key" must be boolean.');
    return value;
  }

  static void _requireKeys(Map<String, Object?> input, Set<String> allowed) {
    if (input.keys.any((key) => !allowed.contains(key))) throw const FormatException('Tool input contains an unsupported field.');
  }
}
