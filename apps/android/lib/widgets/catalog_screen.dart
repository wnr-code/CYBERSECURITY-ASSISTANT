import 'package:material_ui/material_ui.dart';

import '../core/package_manager.dart';
import '../core/tool_orchestrator.dart';
import '../core/tool_registry.dart';
import '../l10n/app_localizations.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.packageManager,
    required this.onOpenAssessment,
  });

  final MarketPackageManager packageManager;
  final VoidCallback onOpenAssessment;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  Set<String> _readyToolIds = const {};
  bool _readinessBusy = true;
  bool _readinessErrorOccurred = false;
  int _readinessGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.packageManager.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageManager != widget.packageManager) {
      oldWidget.packageManager.removeListener(_refresh);
      widget.packageManager.addListener(_refresh);
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_readinessGeneration;
    if (mounted) setState(() => _readinessBusy = true);
    final orchestrator = ToolOrchestrator(packageManager: widget.packageManager);
    final ready = <String>{};
    var hadReadinessError = false;
    final tools = toolRegistry.where((item) => item.id != 'response_analyzer');
    // Resolve readiness concurrently: every check shares the same runtime and
    // package registries, while serial awaits made a stalled platform/storage
    // probe keep the whole catalog in its loading state indefinitely.
    await Future.wait<void>(tools.map((tool) async {
      try {
        final capability = await orchestrator
            .availabilityForTool(tool.id)
            .timeout(const Duration(seconds: 5));
        if (capability.ready) ready.add(tool.id);
        if (capability.status == ToolStatus.error) hadReadinessError = true;
      } catch (_) {
        hadReadinessError = true;
      }
    }));
    if (!mounted || generation != _readinessGeneration) return;
    setState(() {
      _readyToolIds = Set.unmodifiable(ready);
      _readinessErrorOccurred = hadReadinessError;
      _readinessBusy = false;
    });
  }

  @override
  void dispose() {
    widget.packageManager.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  List<ToolDefinition> _visibleTools() {
    final query = _searchController.text.trim().toLowerCase();
    return toolRegistry.where((tool) {
      if (tool.id == 'response_analyzer' || !_readyToolIds.contains(tool.id)) return false;
      return query.isEmpty || '${tool.name} ${tool.description}'.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final tools = _visibleTools();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Security tool catalog'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            children: [
              Text(context.tr('BUILT-IN SECURITY TOOLS'), style: _eyebrow(context)),
              const SizedBox(height: 7),
              Text(context.tr('Security tool catalog'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(context.tr('This list shows built-in checks that passed readiness on this device. Configure Gemini and Cloudflare in Market.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.4)),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: context.tr('Search security tools'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              if (_readinessBusy)
                const LinearProgressIndicator()
              else if (tools.isEmpty)
                Card(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_readyToolIds.isEmpty
                      ? context.tr(_readinessErrorOccurred
                          ? 'Readiness checks failed; affected checks are hidden.'
                          : 'No checks are currently available on this device.')
                      : context.tr('No catalog entries match this search.')),
                ))
              else ...[
                if (_readinessErrorOccurred)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(context.tr('Some checks could not be verified and are hidden.'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                  ),
                for (final tool in tools) ...[
                  _toolCard(context, tool),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolCard(BuildContext context, ToolDefinition tool) => Card(
        key: ValueKey('catalog-tool-${tool.id}'),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF73F0C2).withValues(alpha: .13),
            child: Icon(_iconFor(tool), color: const Color(0xFF73F0C2)),
          ),
          title: Text(tool.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${context.tr('Built-in')} · ${context.tr('Available')}',
                  style: const TextStyle(color: Color(0xFF73F0C2), fontSize: 11)),
              const SizedBox(height: 3),
              Text(context.tr(tool.description), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.35)),
            ]),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          isThreeLine: true,
          onTap: () => _showDetails(tool),
        ),
      );

  Future<void> _showDetails(ToolDefinition tool) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tool.name),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Chip(label: Text(dialogContext.tr('Built-in'))),
                  Chip(label: Text(dialogContext.tr('Available'))),
                ]),
                const SizedBox(height: 8),
                Text(dialogContext.tr(tool.description), style: const TextStyle(height: 1.45)),
                const SizedBox(height: 14),
                Text(dialogContext.tr('Purpose & requirements'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final line in _toolDetails(tool, dialogContext))
                  Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(line, style: const TextStyle(fontSize: 12, height: 1.4))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(dialogContext.tr('Close'))),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pop(context);
                widget.onOpenAssessment();
              },
              icon: const Icon(Icons.radar_rounded),
              label: Text(dialogContext.tr('Open Assessment')),
            ),
          ],
        ),
      );

  List<String> _toolDetails(ToolDefinition tool, BuildContext context) => [
        '${context.tr('Availability')}: ${context.tr('Built-in; not a Market install')}',
        '${context.tr('Platforms')}: ${tool.supportedPlatforms.join(', ')}',
        '${context.tr('Compatibility')}: ${context.tr(_toolCompatibilityLabel(tool.platformCompatibility))}',
        '${context.tr('Required permissions')}: ${tool.requiredPermissions.isEmpty ? context.tr('None') : tool.requiredPermissions.join(', ')}',
        '${context.tr('Required capabilities')}: ${tool.requiredCapabilities.isEmpty ? context.tr('None') : tool.requiredCapabilities.join(', ')}',
        '${context.tr('Runtime')}: ${tool.runtimeId ?? context.tr('None')}',
        '${context.tr('Dependencies')}: ${tool.dependencies.isEmpty ? context.tr('None') : tool.dependencies.join(', ')}',
        '${context.tr('Current readiness')}: ${context.tr('Passed on this device; Assessment verifies readiness again before execution.')}',
        '${context.tr('Documentation')}: ${tool.documentationUrl ?? context.tr('Not published')}',
      ];

  IconData _iconFor(ToolDefinition tool) => switch (tool.id) {
        'dns_lookup' => Icons.hub_outlined,
        'tls_inspector' => Icons.lock_outline,
        'http_headers' => Icons.http_outlined,
        _ => Icons.analytics_outlined,
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
}

TextStyle _eyebrow(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 1.5,
    );
