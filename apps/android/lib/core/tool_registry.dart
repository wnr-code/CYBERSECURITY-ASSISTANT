import 'dart:async';

import 'package_manager.dart';
import 'runtime_manager.dart';

/// Current execution/readiness state. `installed` intentionally differs from
/// `ready`: a registered runtime still has to pass compatibility and health checks.
enum ToolStatus {
  installed,
  ready,
  downloadRequired,
  runtimeRequired,
  dependencyRequired,
  permissionRequired,
  notInstalled,
  environmentRequired,
  limitedCompatibility,
  unsupported,
  disabled,
  error,
}

enum ToolCategory {
  webSecurity,
  networkSecurity,
  osint,
  apkMobileSecurity,
  codeSecurity,
  cloudSecurity,
  vulnerabilityAssessment,
  malwareAnalysis,
  threatIntelligence,
  digitalForensics,
  analysis,
}

enum ToolPlatformCompatibility {
  bundledDartRuntimeCompatible,
  androidArm64Compatible,
  requiresEmbeddedRuntime,
  requiresExternalEnvironment,
  requiresRoot,
  requiresUnsupportedLinuxFeatures,
  requiresRemoteService,
  unsupported,
  notVerified,
}

enum ToolRiskClassification { localAnalysis, passiveNetworkQuery, boundedNetworkCheck, unreviewed }

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.riskClassification,
    required this.platformCompatibility,
    this.version,
    this.repositoryUrl,
    this.license,
    this.supportedPlatforms = const ['Android'],
    this.architectures = const [],
    this.dependencies = const [],
    this.requiredPermissions = const [],
    this.runtimeId,
    this.requiredCapabilities = const {},
    this.executionMethod,
    this.documentationUrl,
    this.marketPackageId,
    this.activeCheck = false,
    this.enabled = true,
  });

  final String id;
  final String name;
  final ToolCategory category;
  final String description;
  /// Null when this application's versioned runtime is the only known version.
  final String? version;
  final String? repositoryUrl;
  /// Null when the tool's standalone license has not been established.
  final String? license;
  final List<String> supportedPlatforms;
  /// Empty means the Dart implementation does not require a native ABI-specific binary.
  final List<String> architectures;
  final String? runtimeId;
  final List<String> dependencies;
  final Set<String> requiredPermissions;
  final Set<String> requiredCapabilities;
  final ToolPlatformCompatibility platformCompatibility;
  final ToolRiskClassification riskClassification;
  final String? executionMethod;
  final String? documentationUrl;
  /// Optional Market metadata association. It never grants execution capability.
  final String? marketPackageId;
  final bool activeCheck;
  final bool enabled;
}

/// The four app-owned P0 tools. Repository/license/version values are only
/// supplied where the project metadata is known; no Market artifact is assumed.
const toolRegistry = <ToolDefinition>[
  ToolDefinition(
    id: 'dns_lookup',
    name: 'DNS Lookup',
    category: ToolCategory.networkSecurity,
    description: 'Resolve and classify A/AAAA addresses using the operating system resolver; other record types are not currently exposed.',
    repositoryUrl: 'https://github.com/wnr-code/CYBERSECURITY-ASSISTANT',
    supportedPlatforms: ['Android', 'Linux'],
    requiredPermissions: {'INTERNET'},
    runtimeId: 'runtime.dart.security-tools',
    requiredCapabilities: {'network'},
    platformCompatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
    riskClassification: ToolRiskClassification.passiveNetworkQuery,
    executionMethod: 'Bundled Dart adapter · dns_lookup',
    marketPackageId: 'tool.dns-lookup',
  ),
  ToolDefinition(
    id: 'tls_inspector',
    name: 'SSL/TLS Inspector',
    category: ToolCategory.webSecurity,
    description: 'Perform standard-port TLS validation and inspect peer certificate identity and validity dates.',
    repositoryUrl: 'https://github.com/wnr-code/CYBERSECURITY-ASSISTANT',
    supportedPlatforms: ['Android', 'Linux'],
    requiredPermissions: {'INTERNET'},
    runtimeId: 'runtime.dart.security-tools',
    requiredCapabilities: {'network'},
    platformCompatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
    riskClassification: ToolRiskClassification.boundedNetworkCheck,
    executionMethod: 'Bundled Dart adapter · tls_inspector',
    activeCheck: true,
  ),
  ToolDefinition(
    id: 'http_headers',
    name: 'HTTP Header Checker',
    category: ToolCategory.webSecurity,
    description: 'Send one bounded HTTPS GET to the selected authorized path and inspect headers and response content.',
    repositoryUrl: 'https://github.com/wnr-code/CYBERSECURITY-ASSISTANT',
    supportedPlatforms: ['Android', 'Linux'],
    requiredPermissions: {'INTERNET'},
    runtimeId: 'runtime.dart.security-tools',
    requiredCapabilities: {'network'},
    platformCompatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
    riskClassification: ToolRiskClassification.boundedNetworkCheck,
    executionMethod: 'Bundled Dart adapter · http_headers',
    activeCheck: true,
  ),
  ToolDefinition(
    id: 'response_analyzer',
    name: 'Security Response Analyzer',
    category: ToolCategory.analysis,
    description: 'Summarize findings produced by local checks without network access.',
    repositoryUrl: 'https://github.com/wnr-code/CYBERSECURITY-ASSISTANT',
    supportedPlatforms: ['Android', 'Linux'],
    requiredPermissions: {},
    runtimeId: 'runtime.dart.security-tools',
    requiredCapabilities: {},
    platformCompatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
    riskClassification: ToolRiskClassification.localAnalysis,
    executionMethod: 'Bundled Dart adapter · response_analyzer',
  ),
];

ToolDefinition? toolById(String id) {
  for (final tool in toolRegistry) {
    if (tool.id == id) return tool;
  }
  return null;
}

class ToolAdapterRegistration {
  const ToolAdapterRegistration({required this.toolId, required this.runtimeId});
  final String toolId;
  final String runtimeId;
}

class ToolAvailability {
  const ToolAvailability({
    required this.definition,
    required this.status,
    required this.compatibility,
    required this.adapterRegistered,
    required this.installed,
    this.reason,
    this.marketPackageStatus,
    this.marketCompatibility,
  });

  final ToolDefinition definition;
  final ToolStatus status;
  final ToolPlatformCompatibility compatibility;
  final bool adapterRegistered;
  final bool installed;
  final String? reason;
  final PackageStatus? marketPackageStatus;
  final PackageCompatibility? marketCompatibility;

  bool get ready => status == ToolStatus.ready;
}

/// Live view over one stable metadata catalog. Execution adapters are indexed
/// from RuntimeManager's reviewed descriptors; Market package metadata is
/// informative only and never registers executable code.
class ToolRegistry {
  ToolRegistry({Iterable<ToolDefinition> definitions = toolRegistry}) {
    for (final definition in definitions) {
      _validateDefinition(definition);
      if (_definitions.containsKey(definition.id)) {
        throw ArgumentError('Tool registry contains duplicate ID "${definition.id}".');
      }
      _definitions[definition.id] = definition;
    }
  }

  final Map<String, ToolDefinition> _definitions = {};
  final Map<String, ToolAdapterRegistration> _adapters = {};
  final Map<String, MarketPackage> _marketPackagesByTool = {};

  List<ToolDefinition> get definitions => List.unmodifiable(_definitions.values);
  List<ToolAdapterRegistration> get adapterRegistrations => List.unmodifiable(_adapters.values);
  ToolDefinition? byId(String id) => _definitions[id];
  ToolAdapterRegistration? adapterFor(String toolId) => _adapters[toolId];
  MarketPackage? marketPackageFor(String toolId) => _marketPackagesByTool[toolId];

  void registerAdapter(ToolAdapterRegistration registration) {
    final definition = _definitions[registration.toolId];
    if (definition == null) throw ArgumentError.value(registration.toolId, 'toolId', 'Tool is not in the registry.');
    if (!definition.enabled) throw StateError('Disabled tools cannot register an execution adapter.');
    if (definition.runtimeId == null || definition.runtimeId != registration.runtimeId) {
      throw ArgumentError('Adapter runtime does not match the tool metadata.');
    }
    if (_adapters.containsKey(registration.toolId)) {
      throw ArgumentError('Tool "${registration.toolId}" already has a registered adapter.');
    }
    _adapters[registration.toolId] = registration;
  }

  bool unregisterAdapter(String toolId) => _adapters.remove(toolId) != null;

  /// Rebuilds only from adapters RuntimeManager actually owns. Package payloads
  /// are deliberately not inspected for code or adapter registrations.
  void synchronizeAdapters(Iterable<RuntimeDescriptor> descriptors, {required Set<String> executableToolIds}) {
    _adapters.clear();
    for (final descriptor in descriptors) {
      for (final toolId in descriptor.supportedToolIds.where(executableToolIds.contains)) {
        final definition = _definitions[toolId];
        if (definition == null || !definition.enabled || definition.runtimeId != descriptor.id) continue;
        registerAdapter(ToolAdapterRegistration(toolId: toolId, runtimeId: descriptor.id));
      }
    }
  }

  /// Reloads catalog associations after package catalog changes. Unknown IDs
  /// are rejected and package installation alone never makes a tool executable.
  void synchronizeMarketPackages(Iterable<MarketPackage> packages) {
    final next = <String, MarketPackage>{};
    for (final package in packages) {
      for (final toolId in package.toolIds) {
        final definition = _definitions[toolId];
        if (definition == null) {
          throw FormatException('Market package "${package.id}" references an unknown tool ID.');
        }
        if (definition.marketPackageId != null && definition.marketPackageId != package.id) {
          throw FormatException('Market package link for "${definition.id}" does not match registry metadata.');
        }
        if (next.containsKey(toolId)) {
          throw FormatException('Multiple Market packages claim the same tool ID "$toolId".');
        }
        next[toolId] = package;
      }
    }
    _marketPackagesByTool
      ..clear()
      ..addAll(next);
  }

  Future<ToolAvailability> resolve(
    String toolId, {
    required RuntimeManager runtimeManager,
    MarketPackageManager? packageManager,
  }) async {
    final definition = _definitions[toolId];
    if (definition == null) {
      return ToolAvailability(
        definition: _unknownTool(toolId),
        status: ToolStatus.unsupported,
        compatibility: ToolPlatformCompatibility.unsupported,
        adapterRegistered: false,
        installed: false,
        reason: 'Unknown tool ID; it is not present in the local registry.',
      );
    }
    if (!definition.enabled) {
      return ToolAvailability(
        definition: definition,
        status: ToolStatus.disabled,
        compatibility: definition.platformCompatibility,
        adapterRegistered: false,
        installed: false,
        reason: 'Tool is disabled by its local registry entry.',
      );
    }
    if (!definition.supportedPlatforms.any((platform) => platform.toLowerCase() == runtimeManager.environment.platform.toLowerCase())) {
      return ToolAvailability(
        definition: definition,
        status: ToolStatus.unsupported,
        compatibility: ToolPlatformCompatibility.unsupported,
        adapterRegistered: false,
        installed: false,
        reason: 'Tool metadata does not list ${runtimeManager.environment.platform} as a supported platform.',
      );
    }

    await runtimeManager.initializeRegistry();
    synchronizeAdapters(runtimeManager.registered, executableToolIds: runtimeManager.executableToolIds);
    if (packageManager != null) {
      await packageManager.initialize();
      synchronizeMarketPackages(packageManager.catalog);
      packageManager.updateAvailableRuntimes(runtimeManager.availableRuntimeIds);
    }
    final registration = _adapters[toolId];
    final package = _marketPackagesByTool[toolId];
    final marketStatus = package == null || packageManager == null ? null : packageManager.statusFor(package);
    final marketCompatibility = package == null || packageManager == null
        ? null
        : packageManager.compatibilityFor(package).status;

    ToolAvailability response({
      required ToolStatus status,
      required String reason,
      bool adapterRegistered = false,
      bool installed = false,
      ToolPlatformCompatibility? compatibility,
    }) => ToolAvailability(
          definition: definition,
          status: status,
          compatibility: compatibility ?? definition.platformCompatibility,
          adapterRegistered: adapterRegistered,
          installed: installed,
          reason: reason,
          marketPackageStatus: marketStatus,
          marketCompatibility: marketCompatibility,
        );

    if (registration == null) {
      return response(
        status: definition.runtimeId == null ? ToolStatus.unsupported : ToolStatus.runtimeRequired,
        reason: definition.runtimeId == null
            ? 'No execution adapter is declared for this tool.'
            : 'The required reviewed runtime adapter is not registered.',
      );
    }

    final runtime = runtimeManager.registered.where((item) => item.id == registration.runtimeId).firstOrNull;
    if (runtime == null) {
      return response(status: ToolStatus.runtimeRequired, reason: 'The required runtime is not registered.');
    }
    final undeclaredCapabilities = definition.requiredCapabilities.difference(runtime.requiredCapabilities.map((capability) => capability.name).toSet());
    if (undeclaredCapabilities.isNotEmpty) {
      return response(
        status: ToolStatus.error,
        reason: 'Reviewed runtime metadata does not declare required tool capabilities: ${undeclaredCapabilities.join(', ')}.',
        adapterRegistered: true,
      );
    }
    final compatibilityReason = runtimeManager.compatibilityProblem(runtime);
    if (compatibilityReason != null) {
      final status = _statusForCompatibilityReason(compatibilityReason);
      return response(
        status: status,
        reason: compatibilityReason,
        adapterRegistered: true,
        compatibility: status == ToolStatus.limitedCompatibility ? ToolPlatformCompatibility.notVerified : ToolPlatformCompatibility.unsupported,
      );
    }

    final discovery = (await runtimeManager.discover()).where((item) => item.descriptor.id == runtime.id).firstOrNull;
    if (discovery == null) {
      return response(status: ToolStatus.runtimeRequired, reason: 'Runtime discovery returned no entry.', adapterRegistered: true);
    }
    switch (discovery.status) {
      case RuntimeDiscoveryStatus.notInstalled:
        return response(status: ToolStatus.runtimeRequired, reason: discovery.reason ?? 'The required runtime is not installed.', adapterRegistered: true);
      case RuntimeDiscoveryStatus.unsupported:
        return response(status: ToolStatus.unsupported, reason: discovery.reason ?? 'The runtime is not compatible with this platform.', adapterRegistered: true, compatibility: ToolPlatformCompatibility.unsupported);
      case RuntimeDiscoveryStatus.environmentRequired:
        final reason = discovery.reason ?? 'The runtime environment is not ready.';
        return response(
          status: _statusForCompatibilityReason(reason),
          reason: reason,
          adapterRegistered: true,
          compatibility: reason.contains('unknown') ? ToolPlatformCompatibility.notVerified : definition.platformCompatibility,
        );
      case RuntimeDiscoveryStatus.available:
        break;
    }

    final state = discovery.state;
    if (state == null || !{
      RuntimeLifecycle.installed,
      RuntimeLifecycle.initialized,
      RuntimeLifecycle.running,
      RuntimeLifecycle.stopped,
    }.contains(state.lifecycle)) {
      return response(
        status: state?.lifecycle == RuntimeLifecycle.failed ? ToolStatus.error : ToolStatus.runtimeRequired,
        reason: state?.lastError ?? 'Runtime installation state is not ready.',
        adapterRegistered: true,
        installed: state != null,
      );
    }
    late final RuntimeState health;
    try {
      health = await runtimeManager.healthCheck(runtime.id).timeout(runtime.resourceLimit.maxExecution);
    } on TimeoutException {
      return response(
        status: ToolStatus.error,
        reason: 'Runtime health check exceeded its declared execution time limit.',
        adapterRegistered: true,
        installed: true,
      );
    } catch (_) {
      return response(
        status: ToolStatus.error,
        reason: 'Runtime health check failed; execution is disabled.',
        adapterRegistered: true,
        installed: true,
      );
    }
    if (health.lifecycle == RuntimeLifecycle.failed || health.lastError != null) {
      return response(
        status: ToolStatus.error,
        reason: health.lastError ?? 'Runtime adapter health check failed; execution is disabled.',
        adapterRegistered: true,
        installed: true,
      );
    }
    return response(status: ToolStatus.ready, reason: 'Reviewed adapter, runtime, and compatibility checks are ready.', adapterRegistered: true, installed: true);
  }

  static ToolStatus _statusForCompatibilityReason(String reason) {
    final normalized = reason.toLowerCase();
    if (normalized.contains('capabilit') || normalized.contains('permission')) return ToolStatus.permissionRequired;
    if (normalized.contains('dependenc')) return ToolStatus.dependencyRequired;
    if (normalized.contains('unknown') || normalized.contains('cannot be confirmed')) return ToolStatus.limitedCompatibility;
    if (normalized.contains('platform') || normalized.contains('abi') || normalized.contains('api')) return ToolStatus.unsupported;
    return ToolStatus.environmentRequired;
  }

  static ToolDefinition _unknownTool(String id) => ToolDefinition(
        id: id.isEmpty || id.length > 64 || !RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(id) ? 'unknown_tool' : id,
        name: 'Unknown tool',
        category: ToolCategory.analysis,
        description: 'Unknown tool IDs are rejected.',
        platformCompatibility: ToolPlatformCompatibility.unsupported,
        riskClassification: ToolRiskClassification.unreviewed,
        enabled: false,
      );

  static void _validateDefinition(ToolDefinition definition) {
    if (!RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(definition.id) ||
        definition.name.trim().isEmpty ||
        definition.description.trim().isEmpty ||
        definition.supportedPlatforms.isEmpty ||
        definition.supportedPlatforms.any((platform) => platform.trim().isEmpty) ||
        definition.architectures.any((architecture) => architecture.trim().isEmpty) ||
        definition.dependencies.toSet().length != definition.dependencies.length ||
        definition.requiredPermissions.any((permission) => permission.trim().isEmpty) ||
        definition.requiredCapabilities.any((capability) => !RuntimeCapability.values.any((known) => known.name == capability)) ||
        definition.marketPackageId != null && !RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(definition.marketPackageId!) ||
        definition.runtimeId != null && !RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(definition.runtimeId!) ||
        definition.version != null && definition.version!.trim().isEmpty ||
        definition.license?.trim().isEmpty == true ||
        definition.repositoryUrl != null && Uri.tryParse(definition.repositoryUrl!)?.scheme != 'https' ||
        definition.documentationUrl != null && Uri.tryParse(definition.documentationUrl!)?.scheme != 'https') {
      throw ArgumentError('Tool registry contains invalid metadata for "${definition.id}".');
    }
  }
}
