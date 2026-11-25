import 'package:material_ui/material_ui.dart';

import '../core/market_provider_manager.dart';
import '../core/package_manager.dart';
import '../core/provider_registry.dart';
import '../core/tool_orchestrator.dart';
import '../core/tool_registry.dart';
import '../l10n/app_localizations.dart';
import 'market_provider_detail_screen.dart';
import 'market_screen.dart';

enum _CatalogGroup { securityTools, developerTools, cloudIntegrations, aiModels, guides }

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.packageManager,
    required this.providerManager,
    required this.onOpenAssessment,
    this.onOpenCloudflareDashboard,
  });

  final MarketPackageManager packageManager;
  final MarketProviderManager providerManager;
  final VoidCallback onOpenAssessment;
  final VoidCallback? onOpenCloudflareDashboard;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  _CatalogGroup? _selectedGroup;
  final Map<String, Future<ToolStatus>> _toolStatuses = {};

  @override
  void initState() {
    super.initState();
    widget.packageManager.addListener(_refresh);
    widget.providerManager.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageManager != widget.packageManager) {
      oldWidget.packageManager.removeListener(_refresh);
      widget.packageManager.addListener(_refresh);
      _toolStatuses.clear();
    }
    if (oldWidget.providerManager != widget.providerManager) {
      oldWidget.providerManager.removeListener(_refresh);
      widget.providerManager.addListener(_refresh);
    }
  }

  void _refresh() {
    _toolStatuses.clear();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.packageManager.removeListener(_refresh);
    widget.providerManager.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  List<_CatalogEntry> _entries() {
    final entries = <_CatalogEntry>[];
    for (final tool in toolRegistry) {
      entries.add(_CatalogEntry(
        id: 'tool.${tool.id}',
        title: tool.name,
        description: tool.description,
        group: _CatalogGroup.securityTools,
        tool: tool,
      ));
    }
    for (final providerId in const ['cloudflare', 'gemini']) {
      final matchingProviders = providerRegistry.where((entry) => entry.id == providerId).toList(growable: false);
      if (matchingProviders.isEmpty) continue;
      final provider = matchingProviders.first;
      entries.add(_CatalogEntry(
        id: 'provider.$providerId',
        title: provider.name,
        description: provider.description,
        group: providerId == 'gemini' ? _CatalogGroup.aiModels : _CatalogGroup.cloudIntegrations,
        providerId: providerId,
        provider: provider,
      ));
    }
    for (final package in widget.packageManager.catalog) {
      final group = switch (package.category) {
        MarketCategory.runtime || MarketCategory.plugins => _CatalogGroup.developerTools,
        MarketCategory.aiModels => _CatalogGroup.aiModels,
        MarketCategory.knowledgePacks => _CatalogGroup.guides,
        MarketCategory.cloudApiConnectors => _CatalogGroup.cloudIntegrations,
        MarketCategory.securityTools => null,
      };
      if (group == null) continue; // Built-in security tools are represented by their actual tool definitions.
      entries.add(_CatalogEntry(
        id: package.id,
        title: package.name,
        description: package.description,
        group: group,
        package: package,
      ));
    }
    final query = _searchController.text.trim().toLowerCase();
    return entries.where((entry) {
      final groupMatches = _selectedGroup == null || entry.group == _selectedGroup;
      final textMatches = query.isEmpty || '${entry.title} ${entry.description} ${_groupName(entry.group)}'.toLowerCase().contains(query);
      return groupMatches && textMatches;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Catalog'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            children: [
              Text(context.tr('DISCOVER CAPABILITIES'), style: _eyebrow(context)),
              const SizedBox(height: 7),
              Text(context.tr('Catalog'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(context.tr('Learn what the app supports, check requirements, then open the relevant workspace or Market manager.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.4)),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: context.tr('Search catalog capabilities'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 6, children: [
                _groupChip(context, null, 'All'),
                for (final group in _CatalogGroup.values) _groupChip(context, group, _groupName(group)),
              ]),
              const SizedBox(height: 14),
              if (entries.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(context.tr('No catalog entries match this search.'))))
              else
                for (final entry in entries) ...[
                  _entryCard(context, entry),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupChip(BuildContext context, _CatalogGroup? group, String label) => FilterChip(
        label: Text(context.tr(label)),
        selected: _selectedGroup == group,
        onSelected: (_) => setState(() => _selectedGroup = group),
      );

  Widget _entryCard(BuildContext context, _CatalogEntry entry) {
    final typeLabel = _typeLabel(entry);
    final status = _statusLabel(entry, context);
    return Card(
      key: ValueKey('catalog-${entry.id}'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF73F0C2).withValues(alpha: .13),
          child: Icon(_iconFor(entry), color: const Color(0xFF73F0C2)),
        ),
        title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${context.tr(_groupName(entry.group))} · ${context.tr(typeLabel)}', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 2),
            if (entry.tool != null)
              FutureBuilder<ToolStatus>(
                future: _toolStatuses.putIfAbsent(entry.tool!.id, () => ToolOrchestrator(packageManager: widget.packageManager).statusForTool(entry.tool!.id)),
                builder: (context, snapshot) {
                  final readiness = snapshot.connectionState != ConnectionState.done
                      ? 'Checking readiness…'
                      : snapshot.hasError || snapshot.data == null
                          ? 'Readiness error'
                          : _toolStatusLabel(snapshot.data!);
                  return Text(
                    '${context.tr('Built-in')} · ${context.tr(readiness)}',
                    style: TextStyle(color: snapshot.data == ToolStatus.ready ? const Color(0xFF73F0C2) : Colors.white70, fontSize: 11),
                  );
                },
              )
            else
              Text(context.tr(status), style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 3),
            Text(context.tr(entry.description), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.35)),
          ]),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        isThreeLine: true,
        onTap: () => _showDetails(entry),
      ),
    );
  }

  Future<void> _showDetails(_CatalogEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, runSpacing: 6, children: [
                Chip(label: Text(context.tr(_typeLabel(entry)))),
                Chip(label: Text(context.tr(_statusLabel(entry, context)))),
              ]),
              const SizedBox(height: 8),
              Text(context.tr(entry.description), style: const TextStyle(height: 1.45)),
              const SizedBox(height: 14),
              Text(context.tr('Purpose & requirements'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ..._details(entry, context).map((line) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(line, style: const TextStyle(fontSize: 12, height: 1.4)),
                  )),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(dialogContext.tr('Close'))),
          ..._actions(entry, dialogContext),
        ],
      ),
    );
  }

  List<Widget> _actions(_CatalogEntry entry, BuildContext dialogContext) {
    if (entry.tool != null) {
      return [
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dialogContext);
            Navigator.pop(context);
            widget.onOpenAssessment();
          },
          icon: const Icon(Icons.radar_rounded),
          label: Text(dialogContext.tr('Open Assessment')),
        ),
      ];
    }
    if (entry.providerId != null) {
      final providerId = entry.providerId!;
      if (providerId == 'local_ai') {
        return [
          FilledButton.icon(
            onPressed: () => _openMarket(dialogContext, initialIndex: 2),
            icon: const Icon(Icons.memory_rounded),
            label: Text(dialogContext.tr('Open AI Models')),
          ),
        ];
      }
      return [
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dialogContext);
            Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => MarketProviderDetailScreen(
                providerId: providerId,
                manager: widget.providerManager,
                onOpenCloudflareDashboard: providerId == 'cloudflare' ? widget.onOpenCloudflareDashboard : null,
              ),
            ));
          },
          icon: const Icon(Icons.link_rounded),
          label: Text(dialogContext.tr('Connect')),
        ),
      ];
    }
    final package = entry.package!;
    final packageStatus = widget.packageManager.statusFor(package);
    final installableNow = packageStatus != PackageStatus.installed &&
        packageStatus != PackageStatus.updateAvailable &&
        widget.packageManager.canInstall(package);
    if (package.category != MarketCategory.aiModels && installableNow) {
      return [
        FilledButton.icon(
          onPressed: () => _openMarket(dialogContext, initialIndex: 1),
          icon: const Icon(Icons.storefront_outlined),
          label: Text(dialogContext.tr('Install')),
        ),
      ];
    }
    if (package.category == MarketCategory.aiModels) {
      return [
        FilledButton.icon(
          onPressed: () => _openMarket(dialogContext, initialIndex: 2),
          icon: const Icon(Icons.memory_rounded),
          label: Text(dialogContext.tr('Open AI Models')),
        ),
      ];
    }
    return [
      OutlinedButton.icon(
        onPressed: () => _openMarket(dialogContext, initialIndex: 1),
        icon: const Icon(Icons.storefront_outlined),
        label: Text(dialogContext.tr('View in Market')),
      ),
    ];
  }

  void _openMarket(BuildContext dialogContext, {required int initialIndex}) {
    Navigator.pop(dialogContext);
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MarketScreen(
        packageManager: widget.packageManager,
        providerManager: widget.providerManager,
        initialIndex: initialIndex,
        onOpenCloudflareDashboard: widget.onOpenCloudflareDashboard,
      ),
    ));
  }

  List<String> _details(_CatalogEntry entry, BuildContext context) {
    final tool = entry.tool;
    if (tool != null) {
      return [
        '${context.tr('Availability')}: ${context.tr('Built-in; not a Market install')}',
        '${context.tr('Platforms')}: ${tool.supportedPlatforms.join(', ')}',
        '${context.tr('Compatibility')}: ${context.tr(_toolCompatibilityLabel(tool.platformCompatibility))}',
        '${context.tr('Required permissions')}: ${tool.requiredPermissions.isEmpty ? context.tr('None') : tool.requiredPermissions.join(', ')}',
        '${context.tr('Required capabilities')}: ${tool.requiredCapabilities.isEmpty ? context.tr('None') : tool.requiredCapabilities.join(', ')}',
        '${context.tr('Runtime')}: ${tool.runtimeId ?? context.tr('None')}',
        '${context.tr('Dependencies')}: ${tool.dependencies.isEmpty ? context.tr('None') : tool.dependencies.join(', ')}',
        '${context.tr('Runtime readiness')}: ${context.tr('Current status is checked when the Assessment workspace opens.')}',
        '${context.tr('Documentation')}: ${tool.documentationUrl ?? context.tr('Not published')}',
        '${context.tr('Current readiness')}: ${context.tr('Readiness is resolved by the bundled runtime when Assessment opens.')}',
      ];
    }
    if (entry.providerId != null) {
      final providerId = entry.providerId!;
      final providerStatus = widget.providerManager.statusFor(providerId);
      return [
        '${context.tr('Connection status')}: ${context.tr(_providerStatusLabel(providerStatus))}',
        if (entry.provider != null) '${context.tr('Authentication')}: ${context.tr(entry.provider!.authType.name)}',
        if (entry.provider != null) '${context.tr('Setup requirements')}: ${context.tr(entry.provider!.setupGuidance)}',
        '${context.tr('Action')}: ${context.tr(providerId == 'local_ai' ? 'Not Ready; inference unavailable' : 'Connect in Provider Manager')}',
        if (providerId == 'cloudflare') context.tr('Only account and zone read endpoints are available; no service write operations are exposed.'),
        if (providerId == 'gemini') context.tr('Uses the existing Gemini adapter; prompt data still requires explicit approval.'),
        if (providerId == 'local_ai') context.tr('No runtime, model download, or inference is implemented.'),
      ];
    }
    final package = entry.package!;
    final compatibility = widget.packageManager.compatibilityFor(package);
    final status = widget.packageManager.statusFor(package);
    return [
      '${context.tr('Market status')}: ${context.tr(_packageStatusLabel(status))}',
      '${context.tr('Compatibility')}: ${context.tr(_packageCompatibilityLabel(compatibility.status))}',
      '${context.tr('Platforms')}: ${package.platforms.join(', ')}',
      '${context.tr('Architectures')}: ${package.architectures.isEmpty ? context.tr('Any') : package.architectures.join(', ')}',
      '${context.tr('Requirements')}: ${package.runtimeRequirements.isEmpty ? context.tr('None') : package.runtimeRequirements.join(', ')}',
      '${context.tr('Permissions')}: ${package.permissions.isEmpty ? context.tr('None') : package.permissions.join(', ')}',
      '${context.tr('License')}: ${package.license ?? context.tr('Not published')}',
      if (compatibility.reasons.isNotEmpty) '${context.tr('Compatibility note')}: ${compatibility.reasons.join(' ')}',
      if (package.installationGuide.isNotEmpty) '${context.tr('Guide')}: ${package.installationGuide}',
    ];
  }

  String _typeLabel(_CatalogEntry entry) {
    if (entry.tool != null) return 'Built-in';
    if (entry.providerId != null && entry.providerId != 'local_ai') return 'Provider';
    if (entry.providerId == 'local_ai') return 'AI Model';
    final package = entry.package!;
    if (package.category == MarketCategory.knowledgePacks) return 'Guide';
    if (package.category == MarketCategory.aiModels) return 'AI Model';
    if (package.category == MarketCategory.cloudApiConnectors) return 'Connector preview';
    final status = widget.packageManager.statusFor(package);
    final canInstallNow = status != PackageStatus.installed && status != PackageStatus.updateAvailable && widget.packageManager.canInstall(package);
    return package.hasArtifact && canInstallNow ? 'Installable package' : 'Planned; unavailable';
  }

  String _statusLabel(_CatalogEntry entry, BuildContext context) {
    if (entry.tool != null) return 'Built-in';
    if (entry.providerId != null) return _providerStatusLabel(widget.providerManager.statusFor(entry.providerId!));
    final package = entry.package!;
    if (package.category == MarketCategory.aiModels) return 'Not Ready';
    return _packageStatusLabel(widget.packageManager.statusFor(package));
  }

  String _providerStatusLabel(ManagedProviderStatus status) => switch (status) {
        ManagedProviderStatus.installed => 'Not connected',
        ManagedProviderStatus.connected => 'Connected',
        ManagedProviderStatus.disconnected => 'Disconnected',
        ManagedProviderStatus.error => 'Error',
        ManagedProviderStatus.notReady => 'Not Ready',
      };

  String _packageStatusLabel(PackageStatus status) => switch (status) {
        PackageStatus.available => 'Available',
        PackageStatus.downloading => 'Downloading',
        PackageStatus.downloaded => 'Downloaded',
        PackageStatus.verifying => 'Verifying',
        PackageStatus.installed => 'Installed',
        PackageStatus.updateAvailable => 'Update Available',
        PackageStatus.incompatible => 'Incompatible',
        PackageStatus.failed => 'Failed',
      };

  String _toolStatusLabel(ToolStatus status) => switch (status) {
        ToolStatus.ready => 'Ready',
        ToolStatus.installed => 'Built-in; readiness not confirmed',
        ToolStatus.downloadRequired => 'Download required; unavailable from Market',
        ToolStatus.runtimeRequired => 'Runtime required',
        ToolStatus.dependencyRequired => 'Dependency required',
        ToolStatus.permissionRequired => 'Permission required',
        ToolStatus.notInstalled => 'Not installed',
        ToolStatus.environmentRequired => 'Environment required',
        ToolStatus.limitedCompatibility => 'Limited compatibility',
        ToolStatus.unsupported => 'Unsupported',
        ToolStatus.disabled => 'Disabled',
        ToolStatus.error => 'Readiness error',
      };

  String _toolCompatibilityLabel(ToolPlatformCompatibility compatibility) => switch (compatibility) {
        ToolPlatformCompatibility.bundledDartRuntimeCompatible => 'Bundled Dart runtime',
        ToolPlatformCompatibility.androidArm64Compatible => 'Android ARM64',
        ToolPlatformCompatibility.requiresEmbeddedRuntime => 'Requires embedded runtime',
        ToolPlatformCompatibility.requiresExternalEnvironment => 'Requires external environment',
        ToolPlatformCompatibility.requiresRoot => 'Requires root',
        ToolPlatformCompatibility.requiresUnsupportedLinuxFeatures => 'Requires unsupported Linux features',
        ToolPlatformCompatibility.requiresRemoteService => 'Requires remote service',
        ToolPlatformCompatibility.unsupported => 'Unsupported',
        ToolPlatformCompatibility.notVerified => 'Not verified',
      };

  String _packageCompatibilityLabel(PackageCompatibility status) => switch (status) {
        PackageCompatibility.compatible => 'Compatible',
        PackageCompatibility.limitedCompatibility => 'Limited Compatibility',
        PackageCompatibility.incompatible => 'Incompatible',
        PackageCompatibility.unsupported => 'Unsupported',
      };

  IconData _iconFor(_CatalogEntry entry) {
    if (entry.tool != null) return entry.tool!.id == 'dns_lookup' ? Icons.hub_outlined : entry.tool!.id == 'tls_inspector' ? Icons.lock_outline : Icons.analytics_outlined;
    if (entry.providerId == 'cloudflare') return Icons.cloud_rounded;
    if (entry.providerId == 'gemini') return Icons.auto_awesome_rounded;
    if (entry.providerId == 'local_ai') return Icons.memory_rounded;
    return switch (entry.group) {
      _CatalogGroup.securityTools => Icons.security_rounded,
      _CatalogGroup.developerTools => Icons.code_rounded,
      _CatalogGroup.cloudIntegrations => Icons.hub_outlined,
      _CatalogGroup.aiModels => Icons.memory_rounded,
      _CatalogGroup.guides => Icons.menu_book_outlined,
    };
  }

  String _groupName(_CatalogGroup group) => switch (group) {
        _CatalogGroup.securityTools => 'Security Tools',
        _CatalogGroup.developerTools => 'Developer Tools',
        _CatalogGroup.cloudIntegrations => 'Cloud Integrations',
        _CatalogGroup.aiModels => 'AI Models',
        _CatalogGroup.guides => 'Guides',
      };
}

class _CatalogEntry {
  const _CatalogEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.group,
    this.tool,
    this.providerId,
    this.provider,
    this.package,
  });
  final String id;
  final String title;
  final String description;
  final _CatalogGroup group;
  final ToolDefinition? tool;
  final String? providerId;
  final ProviderDefinition? provider;
  final MarketPackage? package;
}

TextStyle _eyebrow(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 1.5,
    );
