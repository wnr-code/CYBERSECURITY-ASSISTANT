import 'package:material_ui/material_ui.dart';

import '../core/package_manager.dart';
import '../l10n/app_localizations.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key, required this.packageManager});
  final MarketPackageManager packageManager;

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _searchController = TextEditingController();
  MarketCategory? _selectedCategory;
  late Future<void> _initialization;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.packageManager.addListener(_onPackagesChanged);
    _initialization = widget.packageManager.initialize();
  }

  @override
  void didUpdateWidget(covariant MarketScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageManager != widget.packageManager) {
      oldWidget.packageManager.removeListener(_onPackagesChanged);
      widget.packageManager.addListener(_onPackagesChanged);
      _initialization = widget.packageManager.initialize();
    }
  }

  @override
  void dispose() {
    widget.packageManager.removeListener(_onPackagesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onPackagesChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Market & Package Manager'))),
        body: FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('Package registry could not be loaded safely. No package is marked installed.')),
              ));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return _marketContents(context);
          },
        ),
      );

  Widget _marketContents(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final packages = widget.packageManager.catalog.where((package) {
      final categoryMatches = _selectedCategory == null || package.category == _selectedCategory;
      final searchable = '${package.name} ${package.description} ${package.officialSource} ${package.license ?? ''}'.toLowerCase();
      return categoryMatches && (query.isEmpty || searchable.contains(query));
    }).toList(growable: false);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            Text(context.tr('MARKET'), style: const TextStyle(color: Color(0xFF73F0C2), letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(context.tr('Discover reviewed components'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              context.tr('Install only verified data packages from trusted sources. Downloaded code is never run or loaded by Market.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.45),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Row(children: [
                  const Icon(Icons.inventory_2_outlined, color: Color(0xFF73F0C2)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    '${widget.packageManager.installedPackages.length + widget.packageManager.catalog.where((package) => package.isBundledCore).length} ${context.tr('packages installed')} · ${context.tr('Local-only registry; no developer account or cloud required')}',
                    style: const TextStyle(fontSize: 12),
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.tr('Search packages or categories'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 7, runSpacing: 5, children: [
              FilterChip(
                label: Text(context.tr('All categories')),
                selected: _selectedCategory == null,
                onSelected: (_) => setState(() => _selectedCategory = null),
              ),
              for (final category in MarketCategory.values)
                FilterChip(
                  label: Text(_categoryName(category, context)),
                  selected: _selectedCategory == category,
                  onSelected: (selected) => setState(() => _selectedCategory = selected ? category : null),
                ),
            ]),
            const SizedBox(height: 12),
            if (packages.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(context.tr('No packages match this filter.'))))
            else
              for (final package in packages) ...[
                _packageCard(package, context),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 8),
            Text(
              context.tr('Runtime execution, plugin loading, AI inference, and authenticated cloud connectors are not implemented in this foundation.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _packageCard(MarketPackage package, BuildContext context) {
    final status = widget.packageManager.statusFor(package);
    final compatibility = widget.packageManager.compatibilityFor(package);
    final installed = widget.packageManager.installedById(package.id);
    final canInstall = widget.packageManager.canInstall(package);
    final error = widget.packageManager.errorFor(package.id);
    final progress = status == PackageStatus.downloading ||
        status == PackageStatus.downloaded ||
        status == PackageStatus.verifying;

    return Card(
      key: ValueKey('market-package-${package.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF73F0C2).withValues(alpha: .12),
              child: Icon(_categoryIcon(package.category), color: const Color(0xFF73F0C2)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(package.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text('${_categoryName(package.category, context)} · ${context.tr('Version')} ${package.version}',
                  style: TextStyle(color: Colors.white.withValues(alpha: .67), fontSize: 11)),
            ])),
            const SizedBox(width: 8),
            _statusBadge(status, context),
          ]),
          const SizedBox(height: 9),
          Text(package.description, style: TextStyle(color: Colors.white.withValues(alpha: .8), height: 1.4, fontSize: 12)),
          const SizedBox(height: 8),
          Text('${context.tr('Compatibility')}: ${_compatibilityName(compatibility.status, context)}',
              style: TextStyle(color: _compatibilityColor(compatibility.status), fontSize: 11, fontWeight: FontWeight.w600)),
          if (compatibility.reasons.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 3), child: Text(compatibility.reasons.join(' '), style: const TextStyle(fontSize: 11))),
          if (error != null)
            Padding(padding: const EdgeInsets.only(top: 7), child: Text(error, style: const TextStyle(color: Colors.orangeAccent, fontSize: 11))),
          const SizedBox(height: 7),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text(context.tr('Package details'), style: const TextStyle(fontSize: 12)),
            children: [
              _metadataLine(context, 'Download size', _formatSize(package.downloadSizeBytes, context)),
              _metadataLine(context, 'Official source', '${package.officialSource} · ${package.officialSourceUri.host}'),
              _metadataLine(context, 'License', package.license ?? context.tr('Not published')),
              _metadataLine(context, 'Platforms', package.platforms.join(', ')),
              _metadataLine(context, 'CPU architectures', package.architectures.join(', ')),
              _metadataLine(context, 'Dependencies', package.dependencies.isEmpty ? context.tr('None') : package.dependencies.join(', ')),
              _metadataLine(context, 'Runtime requirements', package.runtimeRequirements.isEmpty ? context.tr('None') : package.runtimeRequirements.join(', ')),
              _metadataLine(context, 'Permissions', package.permissions.isEmpty ? context.tr('None') : package.permissions.join(', ')),
              _metadataLine(context, 'Installation guide', package.installationGuide),
              _metadataLine(context, 'Checksum', package.sha256 ?? context.tr('Not published')),
              _metadataLine(context, 'Package payload', _payloadName(package.payloadType, context)),
              if (installed != null) _metadataLine(context, 'Installed digest', installed.sha256),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 9, runSpacing: 6, children: [
            if (status == PackageStatus.installed && !package.isBundledCore)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _uninstall(package),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.tr('Uninstall')),
              )
            else if (package.isBundledCore)
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(context.tr('Included in core app')),
              )
            else if (status == PackageStatus.updateAvailable)
              FilledButton.icon(
                onPressed: _busy ? null : () => _install(package),
                icon: const Icon(Icons.system_update_alt),
                label: Text(context.tr('Update')),
              )
            else
              FilledButton.icon(
                onPressed: canInstall && !_busy ? () => _install(package) : null,
                icon: progress
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: Text(_actionLabel(package, status, canInstall, context)),
              ),
            if (status == PackageStatus.installed && package.category == MarketCategory.knowledgePacks)
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(context.tr('Knowledge pack data installed')),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _metadataLine(BuildContext context, String key, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('${context.tr(key)}: $value', style: const TextStyle(fontSize: 11, height: 1.35)),
        ),
      );

  Widget _statusBadge(PackageStatus status, BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: _statusColor(status).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _statusColor(status).withValues(alpha: .38)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(_statusName(status, context), style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      );

  Future<void> _install(MarketPackage package) async {
    final accepted = await _confirmLicense(package);
    if (accepted != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.packageManager.install(package, licenseAccepted: true);
    } on Exception catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmLicense(MarketPackage package) {
    final license = package.license;
    if (license == null) return Future<bool?>.value(false);
    return showDialog<bool>(
        context: context,
        builder: (context) {
          var accepted = false;
          return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
                title: Text(context.tr('Review package license')),
                content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${package.name}\n${context.tr('License')}: $license'),
                  const SizedBox(height: 8),
                  Text(package.installationGuide, style: const TextStyle(fontSize: 12)),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: accepted,
                    onChanged: (value) => setDialogState(() => accepted = value ?? false),
                    title: Text(context.tr('I accept this license'), style: const TextStyle(fontSize: 12)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ]),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
                  FilledButton(
                    onPressed: accepted ? () => Navigator.pop(context, true) : null,
                    child: Text(context.tr('Accept & Install')),
                  ),
                ],
              ));
        },
      );
  }

  Future<void> _uninstall(MarketPackage package) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Uninstall package?')),
        content: Text('${context.tr('Remove')} ${package.name}? ${context.tr('Installed package data will be deleted from app-private storage.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Uninstall'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.packageManager.uninstall(package.id);
    } on Exception catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _actionLabel(MarketPackage package, PackageStatus status, bool canInstall, BuildContext context) {
    if (status == PackageStatus.downloading) return context.tr('Downloading…');
    if (status == PackageStatus.downloaded) return context.tr('Downloaded');
    if (status == PackageStatus.verifying) return context.tr('Verifying…');
    if (status == PackageStatus.incompatible) return context.tr('Incompatible');
    if (status == PackageStatus.failed) return canInstall ? context.tr('Retry install') : context.tr('Not installable');
    if (!package.hasArtifact) return context.tr('Catalog metadata only');
    if (!package.canBeInstalledAsData) return context.tr('Not executable from Market');
    return context.tr('Install data package');
  }

  String _formatSize(int? bytes, BuildContext context) {
    if (bytes == null) return context.tr('Not published');
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _categoryName(MarketCategory category, BuildContext context) => context.tr(switch (category) {
        MarketCategory.securityTools => 'Security Tools',
        MarketCategory.runtime => 'Runtime',
        MarketCategory.plugins => 'Plugins',
        MarketCategory.aiModels => 'AI Models',
        MarketCategory.knowledgePacks => 'Knowledge Packs',
        MarketCategory.cloudApiConnectors => 'Cloud/API Connectors',
      });

  String _statusName(PackageStatus status, BuildContext context) => context.tr(switch (status) {
        PackageStatus.available => 'Available',
        PackageStatus.downloading => 'Downloading',
        PackageStatus.downloaded => 'Downloaded',
        PackageStatus.verifying => 'Verifying',
        PackageStatus.installed => 'Installed',
        PackageStatus.updateAvailable => 'Update Available',
        PackageStatus.incompatible => 'Incompatible',
        PackageStatus.failed => 'Failed',
      });

  String _compatibilityName(PackageCompatibility status, BuildContext context) => context.tr(switch (status) {
        PackageCompatibility.compatible => 'Compatible',
        PackageCompatibility.limitedCompatibility => 'Limited Compatibility',
        PackageCompatibility.incompatible => 'Incompatible',
        PackageCompatibility.unsupported => 'Unsupported',
      });

  Color _compatibilityColor(PackageCompatibility status) => switch (status) {
        PackageCompatibility.compatible => const Color(0xFF73F0C2),
        PackageCompatibility.limitedCompatibility => Colors.orangeAccent,
        PackageCompatibility.incompatible || PackageCompatibility.unsupported => Colors.redAccent,
      };

  Color _statusColor(PackageStatus status) => switch (status) {
        PackageStatus.installed => const Color(0xFF73F0C2),
        PackageStatus.downloading || PackageStatus.downloaded || PackageStatus.verifying || PackageStatus.updateAvailable => const Color(0xFF63A5FF),
        PackageStatus.incompatible || PackageStatus.failed => Colors.orangeAccent,
        PackageStatus.available => Colors.white70,
      };

  IconData _categoryIcon(MarketCategory category) => switch (category) {
        MarketCategory.securityTools => Icons.security,
        MarketCategory.runtime => Icons.memory,
        MarketCategory.plugins => Icons.extension,
        MarketCategory.aiModels => Icons.psychology_outlined,
        MarketCategory.knowledgePacks => Icons.menu_book_outlined,
        MarketCategory.cloudApiConnectors => Icons.hub_outlined,
      };

  String _payloadName(PackagePayloadType type, BuildContext context) => context.tr(switch (type) {
        PackagePayloadType.jsonData => 'Validated JSON data',
        PackagePayloadType.opaqueData => 'Opaque data only',
        PackagePayloadType.archive => 'Archive (not installable)',
        PackagePayloadType.nativeExecutable => 'Executable (blocked)',
      });
}
