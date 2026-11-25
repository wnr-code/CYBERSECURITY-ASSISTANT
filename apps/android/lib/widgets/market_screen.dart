import 'package:material_ui/material_ui.dart';

import '../core/market_provider_manager.dart';
import '../core/package_manager.dart';
import '../l10n/app_localizations.dart';
import 'market_provider_detail_screen.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key, required this.packageManager, this.providerManager, this.onOpenCloudflareDashboard, this.initialIndex = 0});
  final MarketPackageManager packageManager;
  final int initialIndex;
  final MarketProviderManager? providerManager;
  final VoidCallback? onOpenCloudflareDashboard;

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
    widget.providerManager?.addListener(_onPackagesChanged);
    _initialization = _initializeManagers();
  }

  @override
  void didUpdateWidget(covariant MarketScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageManager != widget.packageManager) {
      oldWidget.packageManager.removeListener(_onPackagesChanged);
      widget.packageManager.addListener(_onPackagesChanged);
    }
    if (oldWidget.providerManager != widget.providerManager) {
      oldWidget.providerManager?.removeListener(_onPackagesChanged);
      widget.providerManager?.addListener(_onPackagesChanged);
    }
    if (oldWidget.packageManager != widget.packageManager || oldWidget.providerManager != widget.providerManager) {
      _initialization = _initializeManagers();
    }
  }

  Future<void> _initializeManagers() async {
    await widget.packageManager.initialize();
    await widget.providerManager?.initialize();
  }

  @override
  void dispose() {
    widget.packageManager.removeListener(_onPackagesChanged);
    widget.providerManager?.removeListener(_onPackagesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onPackagesChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: widget.providerManager == null ? 1 : widget.initialIndex.clamp(0, 2).toInt(),
        child: Builder(builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(context.tr('Market')),
                bottom: TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: context.tr('Providers')),
                    Tab(text: context.tr('Packages')),
                    Tab(text: context.tr('AI Models')),
                  ],
                ),
              ),
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
                  return TabBarView(children: [
                    _providersContents(context),
                    _marketContents(context),
                    _aiModelsContents(context),
                  ]);
                },
              ),
            )),
      );

  Widget _providersContents(BuildContext context) {
    if (widget.providerManager == null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(context.tr('Provider management is unavailable because the shared Market Provider Manager was not supplied.')),
      ));
    }
    final installedPackages = widget.packageManager.installedPackages.length +
        widget.packageManager.catalog.where((package) => package.isBundledCore).length;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
          Text(context.tr('MARKET'), style: const TextStyle(color: Color(0xFF73F0C2), letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(context.tr('Provider & Security Tools'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          _priorityProviderSection(context),
          const SizedBox(height: 22),
          Row(children: [
            const Icon(Icons.grid_view_rounded, color: Color(0xFF73F0C2)),
            const SizedBox(width: 10),
            Expanded(child: Text(context.tr('Explore Market'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: () => DefaultTabController.of(context).animateTo(1), icon: const Icon(Icons.arrow_forward), label: Text(context.tr('View All'))),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final width = ((constraints.maxWidth - 10) / 2).clamp(120.0, 380.0).toDouble();
            return Wrap(spacing: 10, runSpacing: 10, children: [
              _exploreCard(context, width, Icons.security_rounded, 'Security Tools', 'Security testing and review tools', const Color(0xFF73F0C2),
                  () => _openPackages(context, MarketCategory.securityTools)),
              _exploreCard(context, width, Icons.terminal_rounded, 'Developer Tools', 'Runtime and plugin catalog', const Color(0xFF168DFF),
                  () => _openPackages(context)),
              _exploreCard(context, width, Icons.psychology_rounded, 'AI Models', 'Local model catalog and readiness', const Color(0xFFCB7BFF),
                  () => DefaultTabController.of(context).animateTo(2)),
              _exploreCard(context, width, Icons.cloud_outlined, 'Cloud Services', 'Provider integrations and guides', const Color(0xFF18CDE0),
                  () => _openPackages(context, MarketCategory.cloudApiConnectors)),
            ]);
          }),
          const SizedBox(height: 22),
          Row(children: [
            const Icon(Icons.inventory_2_outlined, color: Color(0xFF20C8FF)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('Installed Tools'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(context.tr('Tools currently included or installed in this app'), style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 12)),
            ])),
            TextButton.icon(onPressed: () => _openPackages(context), icon: const Icon(Icons.arrow_forward), label: Text(context.tr('View All'))),
          ]),
          const SizedBox(height: 8),
          Card(child: ListTile(
            leading: const Icon(Icons.inventory_2_rounded, color: Color(0xFF73F0C2)),
            title: Text(context.tr('Installed Packages')),
            subtitle: Text('$installedPackages ${context.tr('packages installed')}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _openPackages(context),
          )),
        ]),
      ),
    );
  }

  Widget _exploreCard(BuildContext context, double width, IconData icon, String title, String subtitle, Color color, VoidCallback onTap) => SizedBox(
        width: width,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 3),
                Text(context.tr(subtitle), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 11)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF8DB7FF)),
            ])),
          ),
        ),
      );

  void _openPackages(BuildContext context, [MarketCategory? category]) {
    setState(() => _selectedCategory = category);
    DefaultTabController.of(context).animateTo(1);
  }

  Widget _aiModelsContents(BuildContext context) {
    final manager = widget.providerManager;
    final modelPackages = widget.packageManager.catalog.where((package) => package.category == MarketCategory.aiModels).toList(growable: false);
    final localStatus = manager?.statusFor('local_ai') ?? ManagedProviderStatus.notReady;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 30), children: [
          Text(context.tr('AI Models'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(context.tr('Local AI models are separate from cloud AI providers. This catalog does not imply a model is compatible, installed, or runnable.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          Card(child: ListTile(
            leading: const Icon(Icons.memory_rounded, color: Color(0xFF20C8FF)),
            title: Text(context.tr('Local AI')),
            subtitle: Text(context.tr('Google AI Edge / LiteRT-LM runtime and a verified compatible model are not installed.')),
            trailing: _providerStatusBadge(localStatus, context),
            onTap: manager == null ? null : () => _openProviderDetail(context, 'local_ai', manager),
          )),
          const SizedBox(height: 12),
          Text(context.tr('Model Catalog'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(context.tr('Hugging Face and Kaggle are discovery references only. Market does not query or download models from those catalogs.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.4)),
          const SizedBox(height: 10),
          if (modelPackages.isEmpty)
            Text(context.tr('No Local AI model metadata is currently listed.'))
          else
            for (final package in modelPackages) ...[
              _packageCard(package, context),
              const SizedBox(height: 10),
            ],
        ]),
      ),
    );
  }

  Widget _marketContents(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final packages = widget.packageManager.catalog.where((package) {
      final categoryMatches = _selectedCategory == null || package.category == _selectedCategory;
      final searchable = '${package.name} ${package.description} ${package.officialSource} ${package.license ?? ''}'.toLowerCase();
      return categoryMatches && (query.isEmpty || searchable.contains(query));
    }).toList(growable: false);
    final catalogIds = widget.packageManager.catalog.map((package) => package.id).toSet();
    final installedWithoutCatalogEntry = widget.packageManager.installedPackages
        .where((installed) => !catalogIds.contains(installed.id))
        .toList(growable: false);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: ListView(
          key: const ValueKey('market-packages-list'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
          children: [
            Text(context.tr('Packages'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              context.tr('Browse reviewed declarative packages. Downloaded executable code is never run or loaded by Market.'),
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
            if (installedWithoutCatalogEntry.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(context.tr('Installed packages missing from this catalog'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(context.tr('These verified local packages remain removable even if their catalog metadata is no longer available.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.4)),
              for (final installed in installedWithoutCatalogEntry)
                Card(child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFF73F0C2)),
                  title: Text(installed.id),
                  subtitle: Text('${context.tr('Version')} ${installed.version} · ${context.tr('Metadata unavailable in current catalog')}'),
                  trailing: IconButton(
                    tooltip: context.tr('Uninstall'),
                    onPressed: _busy ? null : () => _uninstallInstalledPackage(installed),
                    icon: const Icon(Icons.delete_outline),
                  ),
                )),
            ],
            const SizedBox(height: 8),
            Text(
              context.tr('Market runtime/plugin loading and Local AI inference are not implemented. Gemini and Cloudflare are separate providers with only the capabilities shown in Providers.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityProviderSection(BuildContext context) {
    final manager = widget.providerManager!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.tr('Priority Providers'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(context.tr('Manage the three supported provider entries here. Capabilities and status reflect what this build actually implements. Provider adapters are bundled with the app, so they cannot be uninstalled separately; use Disconnect only to remove that provider credential.'),
          style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.4)),
      const SizedBox(height: 10),
      for (final providerId in MarketProviderManager.priorityProviderIds) ...[
        _priorityProviderCard(providerId, manager, context),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _priorityProviderCard(String providerId, MarketProviderManager manager, BuildContext context) {
    final name = switch (providerId) {
      'cloudflare' => 'Cloudflare',
      'gemini' => 'Gemini',
      _ => 'Local AI',
    };
    final subtitle = switch (providerId) {
      'cloudflare' => context.tr('Cloud infrastructure · token check only; service APIs are not integrated.'),
      'gemini' => context.tr('Cloud AI · existing Gemini adapter with explicit prompt-data approval.'),
      _ => context.tr('On-device AI · runtime and model inference are not integrated.'),
    };
    final status = manager.statusFor(providerId);
    final brandColor = switch (providerId) {
      'cloudflare' => const Color(0xFFF38020),
      'gemini' => const Color(0xFF9A8BFF),
      _ => const Color(0xFF20C8FF),
    };
    final icon = switch (providerId) {
      'cloudflare' => Icons.cloud_rounded,
      'gemini' => Icons.auto_awesome_rounded,
      _ => Icons.memory_rounded,
    };
    return Card(
      key: ValueKey('priority-provider-$providerId'),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openProviderDetail(context, providerId, manager),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
          child: Row(children: [
            CircleAvatar(backgroundColor: brandColor.withValues(alpha: .14), child: Icon(icon, color: brandColor)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11, height: 1.35)),
            ])),
            const SizedBox(width: 8),
            _providerStatusBadge(status, context),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8DB7FF)),
          ]),
        ),
      ),
    );
  }

  Widget _providerStatusBadge(ManagedProviderStatus status, BuildContext context) {
    final color = switch (status) {
      ManagedProviderStatus.installed => const Color(0xFF8DB7FF),
      ManagedProviderStatus.connected => const Color(0xFF73F0C2),
      ManagedProviderStatus.disconnected => Colors.orangeAccent,
      ManagedProviderStatus.error => Colors.redAccent,
      ManagedProviderStatus.notReady => Colors.orangeAccent,
    };
    final label = context.tr(switch (status) {
      ManagedProviderStatus.installed => 'Installed',
      ManagedProviderStatus.connected => 'Connected',
      ManagedProviderStatus.disconnected => 'Disconnected',
      ManagedProviderStatus.error => 'Error',
      ManagedProviderStatus.notReady => 'Not Ready',
    });
    return DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: .42))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _openProviderDetail(BuildContext context, String providerId, MarketProviderManager manager) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MarketProviderDetailScreen(
        providerId: providerId,
        manager: manager,
        onOpenCloudflareDashboard: providerId == 'cloudflare' ? widget.onOpenCloudflareDashboard : null,
      ),
    ));
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
            if (package.isBundledCore)
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(context.tr('Included in core app')),
              )
            else if (status == PackageStatus.updateAvailable ||
                (status == PackageStatus.failed && installed != null && package.version != installed.version))
              FilledButton.icon(
                onPressed: canInstall && !_busy ? () => _install(package) : null,
                icon: const Icon(Icons.system_update_alt),
                label: Text(context.tr(status == PackageStatus.updateAvailable ? 'Update' : 'Retry install')),
              )
            else if (installed == null || progress)
              FilledButton.icon(
                onPressed: canInstall && !_busy ? () => _install(package) : null,
                icon: progress
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: Text(_actionLabel(package, status, canInstall, context)),
              ),
            if (installed != null && !package.isBundledCore)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _uninstall(package),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.tr('Uninstall')),
              ),
            if (installed != null && package.category == MarketCategory.knowledgePacks)
              OutlinedButton.icon(
                onPressed: installed.version == package.version && !_busy ? () => _openKnowledgePack(package) : null,
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(context.tr(installed.version == package.version ? 'Open knowledge pack' : 'Update package to open')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(error.toString()))));
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

  Future<void> _openKnowledgePack(MarketPackage package) async {
    try {
      final manifest = await widget.packageManager.readInstalledJsonData(package);
      final content = manifest['content'];
      if (content is! Map || content['title'] is! String || content['entries'] is! List || (content['entries'] as List).length > 100) {
        throw const PackageManagerException('Knowledge pack content is invalid for safe display.');
      }
      final packTitle = (content['title'] as String).trim();
      if (packTitle.length > 200 || packTitle.codeUnits.any((unit) => unit == 0)) {
        throw const PackageManagerException('Knowledge pack content is invalid for safe display.');
      }
      final entries = <({String title, String text})>[];
      for (final item in content['entries'] as List) {
        if (item is! Map || item['title'] is! String || item['text'] is! String) {
          throw const PackageManagerException('Knowledge pack entry is invalid for safe display.');
        }
        final title = (item['title'] as String).trim();
        final text = (item['text'] as String).trim();
        if (title.isEmpty || title.length > 200 || text.isEmpty || text.length > 8000 || text.codeUnits.any((unit) => unit == 0)) {
          throw const PackageManagerException('Knowledge pack entry exceeds the safe display limits.');
        }
        entries.add((title: title, text: text));
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(packTitle.isEmpty ? package.name : packTitle),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                for (final entry in entries) ...[
                  Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(entry.text, style: const TextStyle(height: 1.45)),
                  const SizedBox(height: 14),
                ],
                if (entries.isEmpty) Text(dialogContext.tr('This knowledge pack contains no readable entries.')),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(dialogContext.tr('Close')))],
        ),
      );
    } on PackageManagerException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(error.message))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Knowledge pack could not be opened safely.'))));
    }
  }

  Future<void> _uninstall(MarketPackage package) => _uninstallById(package.id, package.name);

  Future<void> _uninstallInstalledPackage(InstalledPackage package) => _uninstallById(package.id, package.id);

  Future<void> _uninstallById(String packageId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Uninstall package?')),
        content: Text('${context.tr('Remove')} $displayName? ${context.tr('Installed package data will be deleted from app-private storage.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('Uninstall'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.packageManager.uninstall(packageId);
    } on Exception catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(error.toString()))));
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
