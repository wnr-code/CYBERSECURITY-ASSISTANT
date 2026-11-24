enum ToolStatus { available, notInstalled, environmentRequired, limitedCompatibility, unsupported }

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

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.status,
    required this.activeCheck,
    this.repositoryUrl,
    this.version = '0.1.0',
    this.license = 'Project license to be confirmed',
    this.supportedPlatforms = const ['Android'],
    this.architectures = const ['arm64-v8a', 'x86_64'],
    this.dependencies = const [],
    this.installationMethod = 'Built into the app',
    this.executionMethod = 'Registered Flutter adapter',
    this.requiredPermissions = const ['INTERNET'],
    this.runtimeId = 'runtime.dart.security-tools',
    this.requiredCapabilities = const {'network'},
  });

  final String id;
  final String name;
  final ToolCategory category;
  final String description;
  final ToolStatus status;
  final bool activeCheck;
  final String? repositoryUrl;
  final String version;
  final String license;
  final List<String> supportedPlatforms;
  final List<String> architectures;
  final List<String> dependencies;
  final String installationMethod;
  final String executionMethod;
  final List<String> requiredPermissions;
  final String? runtimeId;
  final Set<String> requiredCapabilities;
}

/// Small, app-owned registry. Entries describe adapters implemented in this app;
/// remote repositories are metadata sources, never executable instructions.
const toolRegistry = <ToolDefinition>[
  ToolDefinition(
    id: 'dns_lookup',
    name: 'DNS Lookup',
    category: ToolCategory.networkSecurity,
    description: 'Resolve and classify A/AAAA addresses using the Android system resolver; other record types are not currently exposed.',
    status: ToolStatus.available,
    activeCheck: false,
  ),
  ToolDefinition(
    id: 'tls_inspector',
    name: 'SSL/TLS Inspector',
    category: ToolCategory.webSecurity,
    description: 'Perform standard-port TLS validation and inspect peer certificate identity and validity dates.',
    status: ToolStatus.available,
    activeCheck: true,
  ),
  ToolDefinition(
    id: 'http_headers',
    name: 'HTTP Header Checker',
    category: ToolCategory.webSecurity,
    description: 'Send one bounded HTTPS GET to the selected authorized path and inspect headers and response content.',
    status: ToolStatus.available,
    activeCheck: true,
  ),
  ToolDefinition(
    id: 'response_analyzer',
    name: 'Security Response Analyzer',
    category: ToolCategory.analysis,
    description: 'Summarize findings produced by local checks.',
    status: ToolStatus.available,
    activeCheck: false,
    requiredPermissions: [],
    requiredCapabilities: {},
  ),
];

ToolDefinition? toolById(String id) {
  for (final tool in toolRegistry) {
    if (tool.id == id) return tool;
  }
  return null;
}
