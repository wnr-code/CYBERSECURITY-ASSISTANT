import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/local_result_store.dart';
import 'core/provider_registry.dart';
import 'core/report_exporter.dart';
import 'core/security_tools.dart';
import 'core/tool_registry.dart';
import 'widgets/provider_details_dialog.dart';
import 'widgets/release_catalog_dialog.dart';
import 'widgets/tool_runner_dialog.dart';

void main() => runApp(const CybersecurityAssistantApp());

const _ink = Color(0xFF0B1020);
const _panel = Color(0xFF151D31);
const _mint = Color(0xFF73F0C2);

class CybersecurityAssistantApp extends StatelessWidget {
  const CybersecurityAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _mint,
      brightness: Brightness.dark,
      surface: _panel,
    );
    return MaterialApp(
      title: 'Cybersecurity Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _ink,
        cardTheme: CardThemeData(
          color: _panel,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _ink,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  final List<ToolRunResult> _recentResults = [];
  final _resultStore = LocalResultStore();
  List<ToolRunResult> _savedResults = [];
  bool _savedHistoryLoaded = false;
  bool _storageBusy = false;
  String? _storageError;

  void _rememberResult(ToolRunResult result) {
    setState(() {
      _recentResults.insert(0, result);
      if (_recentResults.length > 30) _recentResults.removeLast();
    });
  }

  void _clearResults() => setState(_recentResults.clear);

  Future<void> _loadSavedResults() async {
    setState(() {
      _storageBusy = true;
      _storageError = null;
    });
    try {
      final saved = await _resultStore.loadRecent();
      if (!mounted) return;
      setState(() {
        _savedResults = saved;
        _savedHistoryLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _storageError = 'Could not load local history on this device.');
    } finally {
      if (mounted) setState(() => _storageBusy = false);
    }
  }

  Future<bool> _saveResultLocally(ToolRunResult result) async {
    setState(() {
      _storageBusy = true;
      _storageError = null;
    });
    try {
      await _resultStore.save(result);
      final saved = await _resultStore.loadRecent();
      if (!mounted) return false;
      setState(() {
        _savedResults = saved;
        _savedHistoryLoaded = true;
      });
      return true;
    } catch (_) {
      if (mounted) setState(() => _storageError = 'Could not save the result to local history.');
      return false;
    } finally {
      if (mounted) setState(() => _storageBusy = false);
    }
  }

  Future<void> _clearSavedResults() async {
    setState(() {
      _storageBusy = true;
      _storageError = null;
    });
    try {
      await _resultStore.clear();
      if (mounted) setState(() => _savedResults = []);
    } catch (_) {
      if (mounted) setState(() => _storageError = 'Could not clear local history.');
    } finally {
      if (mounted) setState(() => _storageBusy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_resultStore.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardScreen(
        recentResults: List.unmodifiable(_recentResults),
        savedResults: List.unmodifiable(_savedResults),
        savedHistoryLoaded: _savedHistoryLoaded,
        storageBusy: _storageBusy,
        storageError: _storageError,
        onClearResults: _clearResults,
        onLoadSavedResults: _loadSavedResults,
        onSaveResult: _saveResultLocally,
        onClearSavedResults: _clearSavedResults,
      ),
      ToolsScreen(recentResults: List.unmodifiable(_recentResults), onResult: _rememberResult),
      const AssistantScreen(),
      const ConnectionsScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _ink,
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.shield_moon_outlined, color: _mint),
            SizedBox(width: 10),
            Text('CYBERSECURITY', style: TextStyle(fontSize: 14, letterSpacing: 1.2)),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Center(child: _ModeBadge()),
          ),
        ],
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.extension_rounded), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Assistant'),
          NavigationDestination(icon: Icon(Icons.link_rounded), label: 'Connections'),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _mint.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _mint.withValues(alpha: .3)),
        ),
        child: const Text(
          'STANDALONE',
          style: TextStyle(color: _mint, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.recentResults,
    required this.savedResults,
    required this.savedHistoryLoaded,
    required this.storageBusy,
    required this.storageError,
    required this.onClearResults,
    required this.onLoadSavedResults,
    required this.onSaveResult,
    required this.onClearSavedResults,
  });

  final List<ToolRunResult> recentResults;
  final List<ToolRunResult> savedResults;
  final bool savedHistoryLoaded;
  final bool storageBusy;
  final String? storageError;
  final VoidCallback onClearResults;
  final Future<void> Function() onLoadSavedResults;
  final Future<bool> Function(ToolRunResult) onSaveResult;
  final Future<void> Function() onClearSavedResults;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text('SECURITY WORKSPACE', style: _eyebrow(context)),
          const SizedBox(height: 10),
          Text('Your security,\nyour infrastructure.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                  )),
          const SizedBox(height: 12),
          Text(
            'A local-first toolkit for authorized security work. Your data stays on this device unless you choose otherwise.',
            style: TextStyle(color: Colors.white.withValues(alpha: .66), height: 1.5),
          ),
          const SizedBox(height: 24),
          const _QuickStartCard(),
          const SizedBox(height: 22),
          Text('WORKSPACE', style: _eyebrow(context)),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: _StatCard(icon: Icons.extension, value: '4', label: 'P0 tools')),
              SizedBox(width: 12),
              Expanded(child: _StatCard(icon: Icons.cloud_off, value: 'Local', label: 'Data mode')),
            ],
          ),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Recent session checks', icon: Icons.history),
          const SizedBox(height: 6),
          if (recentResults.isNotEmpty)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: () => _confirmClearResults(context, onClearResults),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
              TextButton.icon(
                onPressed: () => _confirmCopyReport(context, recentResults),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy JSON report'),
              ),
            ]),
          const SizedBox(height: 4),
          if (recentResults.isEmpty)
            Text('Checks you save to this session will appear here. They are not persisted yet.',
                style: TextStyle(color: Colors.white.withValues(alpha: .62), height: 1.4))
          else
            for (final result in recentResults.take(3)) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: _mint),
                  title: Text(toolById(result.toolId)?.name ?? result.toolId),
                  subtitle: Text('${result.target} · ${result.summary}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showResultDetails(context, result, onSaveResult: onSaveResult),
                ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Saved on this device', icon: Icons.storage_outlined),
          const SizedBox(height: 6),
          const Text('Saved reports stay in the app-private SQLite database on this device. They are not encrypted or synced.',
              style: TextStyle(height: 1.4)),
          Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (savedHistoryLoaded && savedResults.isNotEmpty)
                TextButton.icon(
                  onPressed: storageBusy ? null : () => _confirmClearSavedResults(context, onClearSavedResults),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear local history'),
                ),
              TextButton.icon(
                onPressed: storageBusy ? null : () => onLoadSavedResults(),
                icon: storageBusy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(savedHistoryLoaded ? 'Refresh' : 'Load history'),
              ),
            ]),
          ),
          if (storageError != null)
            Text(storageError!, style: const TextStyle(color: Colors.orangeAccent)),
          if (savedHistoryLoaded && savedResults.isEmpty)
            Text('No locally saved checks.', style: TextStyle(color: Colors.white.withValues(alpha: .62)))
          else if (!savedHistoryLoaded)
            Text('Load history to view checks saved in SQLite.', style: TextStyle(color: Colors.white.withValues(alpha: .62)))
          else
            for (final result in savedResults.take(10)) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.save_outlined, color: _mint),
                  title: Text(toolById(result.toolId)?.name ?? result.toolId),
                  subtitle: Text('${result.target} · ${result.summary}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showResultDetails(context, result),
                ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Built for responsible testing', icon: Icons.verified_user_outlined),
          const SizedBox(height: 10),
          Text(
            'Only assess systems you own or are explicitly authorized to test. Active checks will require confirmation and validated scope.',
            style: TextStyle(color: Colors.white.withValues(alpha: .66), height: 1.5),
          ),
        ],
      );
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt, color: _mint),
                  SizedBox(width: 8),
                  Text('QUICK START', style: TextStyle(letterSpacing: 1, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Text('Start with a safe, local check',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('DNS, TLS, and HTTP header checks are available. Network checks require a target and your authorization confirmation.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .64), height: 1.45)),
              const SizedBox(height: 16),
              const _StatusPill(label: 'P0 LOCAL CHECKS READY', color: _mint),
            ],
          ),
        ),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: _mint, size: 20),
            const SizedBox(height: 16),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 12)),
          ]),
        ),
      );
}

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, required this.recentResults, required this.onResult});

  final List<ToolRunResult> recentResults;
  final ValueChanged<ToolRunResult> onResult;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final _searchController = TextEditingController();
  ToolCategory? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredTools = toolRegistry.where((tool) {
      final matchesCategory = _selectedCategory == null || tool.category == _selectedCategory;
      final matchesQuery = query.isEmpty ||
          tool.name.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query) ||
          _categoryLabel(tool.category).toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TOOL REGISTRY', style: _eyebrow(context)),
            const SizedBox(height: 8),
            Text('Starter catalog', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Built-in P0 adapters run locally. Network checks require a target and explicit authorization confirmation.',
                style: TextStyle(color: Colors.white.withValues(alpha: .64), height: 1.4)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showReleaseCatalog(context),
                icon: const Icon(Icons.code_rounded),
                label: const Text('Check GitHub releases'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search tools or categories',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilterChip(
                label: const Text('All'),
                selected: _selectedCategory == null,
                onSelected: (_) => setState(() => _selectedCategory = null),
              ),
              for (final category in ToolCategory.values)
                FilterChip(
                  label: Text(_categoryLabel(category)),
                  selected: _selectedCategory == category,
                  onSelected: (selected) => setState(() => _selectedCategory = selected ? category : null),
                ),
            ]),
          ]),
        ),
        Expanded(
          child: filteredTools.isEmpty
              ? const Center(child: Text('No tools match your search.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: filteredTools.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final tool = filteredTools[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: _mint.withValues(alpha: .12),
                          child: Icon(_toolIcon(tool.id), color: _mint),
                        ),
                        title: Text(tool.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${_categoryLabel(tool.category)} · ${tool.status.name.toUpperCase()}\n${tool.description}',
                            style: const TextStyle(height: 1.4),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        isThreeLine: true,
                        onTap: () => _showToolRunner(context, tool, widget.recentResults, widget.onResult),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final List<String> _questions = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('AI ASSISTANT', style: _eyebrow(context)),
                const SizedBox(height: 8),
                Text('Security, with context.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const _AssistantBubble(
                  text: 'Hi! I can help explain the tool catalog and safe testing workflows. AI analysis is not connected yet; avoid sharing secrets or sensitive evidence here.',
                ),
                for (final question in _questions) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      constraints: const BoxConstraints(maxWidth: 300),
                      decoration: BoxDecoration(color: _mint.withValues(alpha: .16), borderRadius: BorderRadius.circular(16)),
                      child: Text(question),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _AssistantBubble(text: 'The AI provider and tool orchestration are not configured in this foundation build.'),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Ask about a tool or workflow…', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _send,
                icon: const Icon(Icons.arrow_upward_rounded),
                style: IconButton.styleFrom(backgroundColor: _mint, foregroundColor: _ink),
              ),
            ]),
          ),
        ],
      );

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _questions.add(text));
    _controller.clear();
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: const TextStyle(height: 1.5)),
      );
}

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _endpointController = TextEditingController();
  final _providerSearchController = TextEditingController();
  ProviderCategory? _selectedProviderCategory;
  String? _status;
  bool _endpointAuthorized = false;
  bool _checking = false;
  bool? _reachable;

  List<ProviderDefinition> get _visibleProviders {
    final query = _providerSearchController.text.trim().toLowerCase();
    return providerRegistry.where((provider) {
      final matchesCategory = _selectedProviderCategory == null || provider.category == _selectedProviderCategory;
      final matchesText = query.isEmpty ||
          provider.name.toLowerCase().contains(query) ||
          provider.description.toLowerCase().contains(query) ||
          providerCategoryLabel(provider.category).toLowerCase().contains(query);
      return matchesCategory && matchesText;
    }).toList();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _providerSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('CONNECTION MANAGER', style: _eyebrow(context)),
          const SizedBox(height: 8),
          Text('Your services, your choice.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Connections are optional. The endpoint stays in memory. Provider credentials can be stored locally for supported auth types, but no provider requests use them.',
              style: TextStyle(color: Colors.white.withValues(alpha: .64), height: 1.45)),
          const SizedBox(height: 18),
          const _SectionTitle(title: 'Test an HTTPS endpoint', icon: Icons.link),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _endpointController,
                  enabled: !_checking,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() {
                    _endpointAuthorized = false;
                    _status = null;
                    _reachable = null;
                  }),
                  decoration: const InputDecoration(labelText: 'Service endpoint', hintText: 'https://api.example.com/health'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _endpointAuthorized,
                  onChanged: _checking ? null : (value) => setState(() => _endpointAuthorized = value ?? false),
                  title: const Text(
                    'I own this endpoint or have explicit permission to test it.',
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _checking || !_endpointAuthorized ? null : _testConnection,
                  icon: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: Text(_checking ? 'Testing…' : 'Test Connection'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  _StatusPill(label: _status!, color: _reachable == true ? _mint : Colors.orangeAccent),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 18),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SectionTitle(title: 'Prototype scope', icon: Icons.info_outline),
                SizedBox(height: 10),
                Text('After you confirm you own or are authorized to test the endpoint, the app sends one unauthenticated HTTPS GET to the entered URL. Redirects are not followed and the response body is discarded. Any HTTP response confirms reachability, not provider authentication or service configuration. The checkbox is a self-attestation, not independent proof. Do not enter URLs containing secrets.', style: TextStyle(height: 1.5)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const _ConnectionRow(name: 'Cloud backend', detail: 'Not configured', icon: Icons.cloud_outlined),
          const SizedBox(height: 10),
          const _ConnectionRow(name: 'AI provider', detail: 'Local / not configured', icon: Icons.auto_awesome_outlined),
          const SizedBox(height: 10),
          const _ConnectionRow(name: 'Cloud storage', detail: 'Not configured', icon: Icons.folder_open_outlined),
          const SizedBox(height: 22),
          const _SectionTitle(title: 'Provider catalog', icon: Icons.apps_outlined),
          const SizedBox(height: 10),
          const Text('Catalog entries are guides only. Local secure credential controls are available for API-key and scoped-token entries; authenticated connectors are not implemented.',
              style: TextStyle(height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: _providerSearchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search providers',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilterChip(
              label: const Text('All'),
              selected: _selectedProviderCategory == null,
              onSelected: (_) => setState(() => _selectedProviderCategory = null),
            ),
            for (final category in ProviderCategory.values)
              FilterChip(
                label: Text(providerCategoryLabel(category)),
                selected: _selectedProviderCategory == category,
                onSelected: (selected) => setState(() => _selectedProviderCategory = selected ? category : null),
              ),
          ]),
          const SizedBox(height: 8),
          for (final provider in _visibleProviders) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.link_outlined, color: _mint),
                title: Text(provider.name),
                subtitle: Text('${providerCategoryLabel(provider.category)} · NOT CONNECTED\n${provider.description}'),
                trailing: const Icon(Icons.info_outline),
                isThreeLine: true,
                onTap: () => _showProviderDetails(context, provider),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      );

  Uri? _parseConnectionEndpoint(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null) return null;
    try {
      final port = uri.port;
      if (uri.scheme != 'https' ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          port < 1 ||
          port > 65535) {
        return null;
      }
    } on FormatException {
      return null;
    }
    return uri;
  }

  Future<void> _testConnection() async {
    if (!_endpointAuthorized) {
      setState(() {
        _reachable = false;
        _status = 'Confirm that you own or are authorized to test this endpoint';
      });
      return;
    }
    final uri = _parseConnectionEndpoint(_endpointController.text.trim());
    if (uri == null) {
      setState(() {
        _reachable = false;
        _status = 'Enter a valid HTTPS URL without credentials, query, or fragment';
      });
      return;
    }

    setState(() {
      _checking = true;
      _status = null;
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
      final response = await request.close().timeout(const Duration(seconds: 8));
      final code = response.statusCode;
      await response.listen((_) {}).cancel();
      if (!mounted) return;
      setState(() {
        _reachable = true;
        _status = code >= 300 && code < 400
            ? 'Endpoint reached (HTTP $code; redirect not followed)'
            : 'Endpoint reached (HTTP $code)';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = 'Timed out while contacting the endpoint';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = 'Could not reach endpoint; check URL and network';
      });
    } on HandshakeException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = 'TLS certificate validation failed';
      });
    } on HttpException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = 'HTTP request failed';
      });
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _checking = false);
    }
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.name, required this.detail, required this.icon});
  final String name;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: _mint),
          title: Text(name),
          subtitle: Text(detail),
          trailing: const Icon(Icons.add_link_rounded),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: _mint),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]);
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

TextStyle _eyebrow(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 1.5,
    );

String _categoryLabel(ToolCategory category) => switch (category) {
      ToolCategory.webSecurity => 'WEB SECURITY',
      ToolCategory.networkSecurity => 'NETWORK SECURITY',
      ToolCategory.analysis => 'ANALYSIS',
    };

IconData _toolIcon(String id) => switch (id) {
      'dns_lookup' => Icons.hub_outlined,
      'tls_inspector' => Icons.lock_outline,
      'http_headers' => Icons.http_outlined,
      _ => Icons.analytics_outlined,
    };

void _showProviderDetails(BuildContext context, ProviderDefinition provider) {
  showDialog<void>(
    context: context,
    builder: (_) => ProviderDetailsDialog(provider: provider),
  );
}

Future<void> _showReleaseCatalog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const ReleaseCatalogDialog(),
    );

Future<bool?> _confirmSaveResult(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save this result locally?'),
        content: const Text(
          'This stores the target, response details, findings, and authorization self-attestation in the app-private SQLite database. The database is not encrypted and is not synced to the cloud. Continue only if this is appropriate for your device.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Save locally')),
        ],
      ),
    );

Future<void> _confirmClearSavedResults(BuildContext context, Future<void> Function() onClear) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clear local history?'),
      content: const Text('This permanently deletes saved results from the app-private database on this device.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete local history')),
      ],
    ),
  );
  if (confirmed == true) await onClear();
}

Future<void> _confirmClearResults(BuildContext context, VoidCallback onClear) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clear session results?'),
      content: const Text('This removes the in-memory results from this session. It does not clear reports already copied to the clipboard.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Clear results')),
      ],
    ),
  );
  if (confirmed == true) onClear();
}

Future<void> _confirmCopyReport(BuildContext context, List<ToolRunResult> results) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Copy session report?'),
      content: const Text(
        'The report includes assessed hostnames, resolved addresses, certificate details, response headers, and findings. It will be copied to the system clipboard, which other apps may be able to read. Continue only if you are comfortable sharing this data.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Copy report')),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await Clipboard.setData(ClipboardData(text: buildSessionReportJson(results)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session report copied to clipboard.')));
    }
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not access the system clipboard.')));
    }
  }
}

Future<void> _showToolRunner(
  BuildContext context,
  ToolDefinition tool,
  List<ToolRunResult> recentResults,
  ValueChanged<ToolRunResult> onResult,
) async {
  final result = await showDialog<ToolRunResult>(
    context: context,
    builder: (_) => ToolRunnerDialog(tool: tool, recentResults: recentResults),
  );
  if (result != null) onResult(result);
}

void _showResultDetails(
  BuildContext context,
  ToolRunResult result, {
  Future<bool> Function(ToolRunResult)? onSaveResult,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(toolById(result.toolId)?.name ?? result.toolId),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${result.target} · ${result.completedAt.toLocal()}'),
            if (result.toolId != 'response_analyzer')
              Text('Authorization confirmation accepted: ${result.authorizationConfirmed} (self-attestation only)'),
            const SizedBox(height: 8),
            Text(result.summary, style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final finding in result.findings) ...[
              const SizedBox(height: 10),
              Text('${finding.severity.name.toUpperCase()} · ${finding.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(finding.recommendation),
            ],
            if (result.details.isNotEmpty) ...[
              const Divider(height: 24),
              for (final detail in result.details)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: SelectableText(detail)),
            ],
          ]),
        ),
      ),
      actions: [
        if (onSaveResult != null && result.toolId != 'response_analyzer')
          TextButton(
            onPressed: () async {
              final confirmed = await _confirmSaveResult(context);
              if (confirmed != true || !context.mounted) return;
              final saved = await onSaveResult(result);
              if (!context.mounted) return;
              if (saved) {
                Navigator.of(context).pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save local result.')));
              }
            },
            child: const Text('Save on device'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    ),
  );
}
