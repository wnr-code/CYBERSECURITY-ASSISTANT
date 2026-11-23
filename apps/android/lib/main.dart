import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;

import 'core/local_result_store.dart';
import 'core/provider_registry.dart';
import 'core/report_exporter.dart';
import 'core/security_tools.dart';
import 'core/tool_registry.dart';
import 'l10n/app_localizations.dart';
import 'widgets/provider_details_dialog.dart';
import 'widgets/release_catalog_dialog.dart';
import 'widgets/tool_runner_dialog.dart';

void main() => runApp(const CybersecurityAssistantApp());

const _ink = Color(0xFF0B1020);
const _panel = Color(0xFF151D31);
const _mint = Color(0xFF73F0C2);

class CybersecurityAssistantApp extends StatefulWidget {
  const CybersecurityAssistantApp({super.key});

  @override
  State<CybersecurityAssistantApp> createState() => _CybersecurityAssistantAppState();
}

class _CybersecurityAssistantAppState extends State<CybersecurityAssistantApp> {
  Locale _locale = const Locale('id');

  void _setLocale(Locale locale) => setState(() => _locale = locale);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _mint,
      brightness: Brightness.dark,
      surface: _panel,
    );
    return MaterialApp(
      title: 'Cybersecurity Assistant',
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'sans-serif',
        colorScheme: scheme,
        scaffoldBackgroundColor: _ink,
        cardTheme: CardThemeData(
          color: _panel,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0, scrolledUnderElevation: 0),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
      home: MainShell(onLocaleChanged: _setLocale),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.resultStore, this.onLocaleChanged});

  final ResultHistoryStore? resultStore;
  final ValueChanged<Locale>? onLocaleChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  final List<ToolRunResult> _recentResults = [];
  late final ResultHistoryStore _resultStore;
  List<ToolRunResult> _savedResults = [];
  bool _savedHistoryLoaded = false;
  bool _storageBusy = false;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _resultStore = widget.resultStore ?? LocalResultStore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadSavedResults());
    });
  }

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
    final wideLayout = MediaQuery.sizeOf(context).width >= 720;
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
        onNavigateToTools: () => setState(() => _selectedIndex = 1),
      ),
      ToolsScreen(recentResults: List.unmodifiable(_recentResults), onResult: _rememberResult),
      AssistantScreen(
        onOpenConnections: () => setState(() => _selectedIndex = 3),
        onOpenTools: () => setState(() => _selectedIndex = 1),
      ),
      const ConnectionsScreen(),
    ];
    final labels = [context.tr('Home'), context.tr('Tools'), context.tr('Assistant'), context.tr('Connections')];
    final icons = [Icons.grid_view_rounded, Icons.extension_rounded, Icons.auto_awesome, Icons.link_rounded];
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
        actions: [
          const Center(child: _ModeBadge()),
          if (widget.onLocaleChanged != null)
            PopupMenuButton<String>(
              tooltip: context.tr('Language'),
              icon: const Icon(Icons.language),
              onSelected: (code) => widget.onLocaleChanged!(Locale(code)),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'id', child: Text(context.tr('Bahasa Indonesia'))),
                PopupMenuItem(value: 'en', child: Text(context.tr('English'))),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Row(children: [
          if (wideLayout)
            NavigationRail(
              selectedIndex: _selectedIndex,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              destinations: [
                for (var index = 0; index < labels.length; index++)
                  NavigationRailDestination(icon: Icon(icons[index]), label: Text(labels[index])),
              ],
            ),
          Expanded(child: pages[_selectedIndex]),
        ]),
      ),
      bottomNavigationBar: wideLayout
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              destinations: [
                for (var index = 0; index < labels.length; index++)
                  NavigationDestination(icon: Icon(icons[index]), label: labels[index]),
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
        child: Text(
          context.tr('STANDALONE'),
          style: const TextStyle(color: _mint, fontSize: 10, fontWeight: FontWeight.w700),
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
    required this.onNavigateToTools,
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
  final VoidCallback onNavigateToTools;

  @override
  Widget build(BuildContext context) {
    final availableTools = toolRegistry.where((tool) => tool.status == ToolStatus.available).length;
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text(context.tr('RUANG KERJA KEAMANAN'), style: _eyebrow(context)),
        const SizedBox(height: 8),
        Text(context.tr('Keamanan digital, kendali tetap di tangan Anda.'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.12)),
        const SizedBox(height: 10),
        Text(context.tr('Pemeriksaan berjalan di perangkat Anda. Koneksi AI dan layanan cloud bersifat opsional.'),
            style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.5)),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.shield_outlined, color: _mint),
                const SizedBox(width: 8),
                Text(context.tr('MODE LOKAL'), style: const TextStyle(color: _mint, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              Text(context.tr('Mulai pemeriksaan yang Anda izinkan'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(context.tr('DNS, sertifikat TLS, dan header HTTP. Data sesi tidak keluar dari perangkat kecuali Anda memilih membagikannya.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .7), height: 1.45)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onNavigateToTools,
                icon: const Icon(Icons.arrow_forward),
                label: Text(context.tr('Buka katalog alat')),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _DashboardMetric(icon: Icons.extension_outlined, value: '$availableTools', label: context.tr('Alat aktif')),
          _DashboardMetric(icon: Icons.history, value: '${recentResults.length}', label: context.tr('Hasil sesi')),
          _DashboardMetric(icon: Icons.storage_outlined, value: savedHistoryLoaded ? '${savedResults.length}' : '…', label: context.tr('Hasil tersimpan')),
        ]),
        const SizedBox(height: 26),
        _DashboardSectionHeader(
          title: context.tr('Pemeriksaan sesi'),
          icon: Icons.bolt_outlined,
          action: recentResults.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => _confirmCopyReport(context, recentResults),
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(context.tr('Salin laporan JSON')),
                ),
        ),
        const SizedBox(height: 10),
        if (recentResults.isEmpty)
          _EmptyState(
            icon: Icons.manage_search,
            title: context.tr('Belum ada pemeriksaan'),
            detail: context.tr('Jalankan alat dari katalog. Hasil sesi sementara akan muncul di sini.'),
            action: TextButton(onPressed: onNavigateToTools, child: Text(context.tr('Pilih alat'))),
          )
        else ...[
          for (final result in recentResults.take(3)) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline, color: _mint),
                title: Text(_toolDisplayName(result.toolId, context)),
                subtitle: Text('${result.target} · ${_displayResultSummary(result.summary, context)}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showResultDetails(context, result, onSaveResult: onSaveResult),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _confirmClearResults(context, onClearResults),
              icon: const Icon(Icons.delete_outline),
              label: Text(context.tr('Hapus sesi')),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _DashboardSectionHeader(
          title: context.tr('Riwayat di perangkat'),
          icon: Icons.storage_outlined,
          action: Row(mainAxisSize: MainAxisSize.min, children: [
            if (savedHistoryLoaded && savedResults.isNotEmpty)
              TextButton.icon(
                onPressed: storageBusy ? null : () => _confirmClearSavedResults(context, onClearSavedResults),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.tr('Hapus riwayat')),
              ),
            TextButton.icon(
              onPressed: storageBusy ? null : () => onLoadSavedResults(),
              icon: storageBusy
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(context.tr('Muat ulang')),
            ),
          ]),
        ),
        Text(context.tr('Disimpan lokal di SQLite privat aplikasi; tidak dienkripsi atau disinkronkan.'),
            style: TextStyle(color: Colors.white.withValues(alpha: .68), height: 1.4)),
        if (storageError != null) ...[
          const SizedBox(height: 8),
          Text(_translateStorageError(context, storageError!), style: const TextStyle(color: Colors.orangeAccent)),
        ],
        const SizedBox(height: 10),
        if (storageBusy && savedResults.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
        else if (savedHistoryLoaded && savedResults.isEmpty)
          _EmptyState(
            icon: Icons.inventory_2_outlined,
            title: context.tr('Belum ada riwayat tersimpan'),
            detail: context.tr('Simpan hasil pemeriksaan dari detail hasil agar dapat dibuka lagi setelah aplikasi ditutup.'),
          )
        else
          for (final result in savedResults.take(10)) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.save_outlined, color: _mint),
                title: Text(_toolDisplayName(result.toolId, context)),
                subtitle: Text('${result.target} · ${_displayResultSummary(result.summary, context)}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showResultDetails(context, result),
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 20),
        Text(context.tr('Periksa hanya sistem yang Anda miliki atau yang memberi Anda izin. Konfirmasi di aplikasi bukan bukti izin hukum.'),
            style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 12, height: 1.45)),
      ],
    );

    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: content));
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 180,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icon, color: _mint),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12)),
              ])),
            ]),
          ),
        ),
      );
}

class _DashboardSectionHeader extends StatelessWidget {
  const _DashboardSectionHeader({required this.title, required this.icon, this.action});
  final String title;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 19, color: _mint),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        if (action != null) action!,
      ]);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.detail, this.action});
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: _mint),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(detail, style: TextStyle(color: Colors.white.withValues(alpha: .68), height: 1.4)),
              if (action != null) Align(alignment: Alignment.centerLeft, child: action!),
            ])),
          ]),
        ),
      );
}

String _toolDisplayName(String toolId, BuildContext context) => switch (toolId) {
      'dns_lookup' => context.tr('Pencarian DNS'),
      'tls_inspector' => context.tr('Inspeksi Sertifikat TLS'),
      'http_headers' => context.tr('Pemeriksa Header HTTP'),
      'response_analyzer' => context.tr('Analisis Temuan'),
      _ => toolId,
    };

String _translateStorageError(BuildContext context, String error) => switch (error) {
      'Could not load local history on this device.' => context.tr('Riwayat lokal tidak dapat dimuat.'),
      'Could not save the result to local history.' => context.tr('Hasil tidak dapat disimpan ke riwayat lokal.'),
      'Could not clear local history.' => context.tr('Riwayat lokal tidak dapat dihapus.'),
      _ => error,
    };

String _displayResultSummary(String summary, BuildContext context) {
  final locale = AppLocalizations.of(context).locale.languageCode;
  final dns = RegExp(r'^Resolved (\d+) address(?:es)?\.$').firstMatch(summary);
  if (dns != null) {
    final count = dns.group(1)!;
    return locale == 'id' ? 'Menemukan $count alamat IP.' : 'Resolved $count address${count == '1' ? '' : 'es'}.';
  }
  final tls = RegExp(r'^TLS handshake succeeded; certificate expires (.+)\.$').firstMatch(summary);
  if (tls != null) return locale == 'id' ? 'Handshake TLS berhasil; sertifikat berlaku hingga ${tls.group(1)}.' : summary;
  final http = RegExp(r'^Received HTTP (\d+) and inspected (\d+) response headers\.$').firstMatch(summary);
  if (http != null && locale == 'id') return 'Respons HTTP ${http.group(1)} · ${http.group(2)} header diperiksa.';
  final analyzer = RegExp(r'^(\d+) finding(s?) across (\d+) check(s?)\.$').firstMatch(summary);
  if (analyzer != null && locale == 'id') return '${analyzer.group(1)} temuan dari ${analyzer.group(3)} pemeriksaan.';
  if (summary == 'No findings were produced by the completed checks.' && locale == 'id') return 'Tidak ada temuan dari pemeriksaan yang selesai.';
  return summary;
}

String _displayResultDetail(String detail, BuildContext context) {
  final locale = AppLocalizations.of(context).locale.languageCode;
  if (locale != 'id') return detail;
  const labels = {
    'Subject: ': 'Subjek: ',
    'Issuer: ': 'Penerbit: ',
    'Valid from: ': 'Berlaku sejak: ',
    'Valid until: ': 'Berlaku hingga: ',
    'Days remaining: ': 'Sisa hari: ',
    'Trust validation: passed by the device TLS stack': 'Validasi kepercayaan: lolos pada sistem TLS perangkat',
    'The response contained no headers.': 'Respons tidak berisi header.',
    'Redirect returned; it was not followed.': 'Server mengirim pengalihan; pengalihan tidak diikuti.',
  };
  for (final entry in labels.entries) {
    if (detail.startsWith(entry.key)) return '${entry.value}${detail.substring(entry.key.length)}';
  }
  return detail;
}

String _displayFindingTitle(String title, BuildContext context) {
  final locale = AppLocalizations.of(context).locale.languageCode;
  if (locale != 'id') return title;
  final expiry = RegExp(r'^Certificate expires in (-?\d+) day\(s\)$').firstMatch(title);
  if (expiry != null) return 'Sertifikat kedaluwarsa dalam ${expiry.group(1)} hari';
  final missing = RegExp(r'^(.*) header not observed$').firstMatch(title);
  if (missing != null) {
    final header = switch (missing.group(1)) {
      'HTTP Strict Transport Security (HSTS)' => 'HTTP Strict Transport Security (HSTS)',
      'Content Security Policy (CSP)' => 'Content Security Policy (CSP)',
      'X-Content-Type-Options' => 'X-Content-Type-Options',
      'Referrer-Policy' => 'Referrer-Policy',
      'Permissions-Policy' => 'Permissions-Policy',
      _ => missing.group(1)!,
    };
    return 'Header $header tidak ditemukan';
  }
  if (title == 'Server technology header is exposed') return 'Header teknologi server terlihat';
  return title;
}

String _severityName(FindingSeverity severity, BuildContext context) => switch (severity) {
      FindingSeverity.high => context.tr('TINGGI'),
      FindingSeverity.medium => context.tr('SEDANG'),
      FindingSeverity.low => context.tr('RENDAH'),
      FindingSeverity.info => context.tr('INFO'),
    };

String _displayRecommendation(String recommendation, BuildContext context) => context.tr(recommendation);

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
          _toolDisplayName(tool.id, context).toLowerCase().contains(query) ||
          _toolDisplayDescription(tool.id, context).toLowerCase().contains(query) ||
          _categoryLabel(tool.category, context).toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('KATALOG ALAT'), style: _eyebrow(context)),
            const SizedBox(height: 8),
            Text(context.tr('Pemeriksaan keamanan'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(context.tr('Alat bawaan berjalan di perangkat. Pemeriksaan jaringan memerlukan target dan konfirmasi izin.'),
                style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.45)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showReleaseCatalog(context),
                icon: const Icon(Icons.code_rounded),
                label: Text(context.tr('Lihat rilis GitHub')),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.tr('Cari alat atau kategori'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilterChip(
                label: Text(context.tr('Semua')),
                selected: _selectedCategory == null,
                onSelected: (_) => setState(() => _selectedCategory = null),
              ),
              for (final category in ToolCategory.values)
                FilterChip(
                  label: Text(_categoryLabel(category, context)),
                  selected: _selectedCategory == category,
                  onSelected: (selected) => setState(() => _selectedCategory = selected ? category : null),
                ),
            ]),
          ]),
        ),
        Expanded(
          child: filteredTools.isEmpty
              ? Center(child: Text(context.tr('Tidak ada alat yang cocok dengan pencarian.')))
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
                        title: Text(_toolDisplayName(tool.id, context), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${_categoryLabel(tool.category, context)} · ${_toolStatusLabel(tool.status, context)}\n${_toolDisplayDescription(tool.id, context)}',
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

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key, required this.onOpenConnections, required this.onOpenTools});

  final VoidCallback onOpenConnections;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(context.tr('ASISTEN AI'), style: _eyebrow(context)),
            const SizedBox(height: 8),
            Text(context.tr('Bantuan berbasis AI'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, color: _mint, size: 28),
                  const SizedBox(height: 12),
                  Text(context.tr('Asisten AI belum terhubung'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(context.tr('Belum ada pesan yang dikirim ke penyedia AI. Koneksi provider dan analisis AI belum diimplementasikan. Jangan masukkan API key atau data sensitif di layar ini.'),
                      style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.5)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 8, children: [
                    OutlinedButton.icon(onPressed: onOpenConnections, icon: const Icon(Icons.link), label: Text(context.tr('Lihat pusat koneksi'))),
                    FilledButton.icon(onPressed: onOpenTools, icon: const Icon(Icons.extension_outlined), label: Text(context.tr('Gunakan alat lokal'))),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
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

  List<ProviderDefinition> _visibleProviders(BuildContext context) {
    final query = _providerSearchController.text.trim().toLowerCase();
    return providerRegistry.where((provider) {
      final matchesCategory = _selectedProviderCategory == null || provider.category == _selectedProviderCategory;
      final matchesText = query.isEmpty ||
          provider.name.toLowerCase().contains(query) ||
          _providerDescription(provider, context).toLowerCase().contains(query) ||
          _providerCategoryName(provider.category, context).toLowerCase().contains(query);
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
          Text(context.tr('PUSAT KONEKSI'), style: _eyebrow(context)),
          const SizedBox(height: 8),
          Text(context.tr('Infrastruktur pilihan Anda'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(context.tr('Koneksi bersifat opsional. Pemeriksaan lokal tetap berjalan tanpa akun cloud atau API key. Informasi provider di bawah adalah panduan; konektor terautentikasi belum tersedia.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.45)),
          const SizedBox(height: 18),
          _SectionTitle(title: context.tr('Uji endpoint HTTPS'), icon: Icons.link),
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
                  decoration: InputDecoration(labelText: context.tr('Alamat endpoint'), hintText: 'https://api.example.com'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _endpointAuthorized,
                  onChanged: _checking ? null : (value) => setState(() => _endpointAuthorized = value ?? false),
                  title: Text(
                    context.tr('Saya memiliki endpoint ini atau mendapat izin untuk mengujinya.'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _checking || !_endpointAuthorized ? null : _testConnection,
                  icon: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: Text(_checking ? context.tr('Menguji…') : context.tr('Uji koneksi')),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  _StatusPill(label: _status!, color: _reachable == true ? _mint : Colors.orangeAccent),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SectionTitle(title: context.tr('Batasan uji koneksi'), icon: Icons.info_outline),
                const SizedBox(height: 10),
                Text(context.tr('Setelah Anda mengonfirmasi izin, aplikasi mengirim satu HTTPS GET tanpa autentikasi ke alamat yang dimasukkan. Pengalihan tidak diikuti dan isi respons dibuang. Respons HTTP apa pun hanya menandakan endpoint terjangkau, bukan autentikasi provider. Jangan masukkan URL yang berisi rahasia.'), style: const TextStyle(height: 1.5)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _ConnectionRow(name: context.tr('Backend cloud'), detail: context.tr('Belum dikonfigurasi'), icon: Icons.cloud_outlined),
          const SizedBox(height: 10),
          _ConnectionRow(name: context.tr('Penyedia AI'), detail: context.tr('Belum diuji'), icon: Icons.auto_awesome_outlined),
          const SizedBox(height: 10),
          _ConnectionRow(name: context.tr('Penyimpanan cloud'), detail: context.tr('Belum dikonfigurasi'), icon: Icons.folder_open_outlined),
          const SizedBox(height: 22),
          _SectionTitle(title: context.tr('Katalog penyedia layanan'), icon: Icons.apps_outlined),
          const SizedBox(height: 10),
          Text(context.tr('Katalog ini berisi panduan, bukan konektor aktif. Kredensial hanya dapat disimpan lokal untuk beberapa jenis; belum ada permintaan provider yang menggunakan kredensial tersebut.'),
              style: const TextStyle(height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: _providerSearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('Cari penyedia layanan'),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilterChip(
              label: Text(context.tr('Semua')),
              selected: _selectedProviderCategory == null,
              onSelected: (_) => setState(() => _selectedProviderCategory = null),
            ),
            for (final category in ProviderCategory.values)
              FilterChip(
                label: Text(_providerCategoryName(category, context)),
                selected: _selectedProviderCategory == category,
                onSelected: (selected) => setState(() => _selectedProviderCategory = selected ? category : null),
              ),
          ]),
          const SizedBox(height: 8),
          if (_visibleProviders(context).isEmpty)
            _EmptyState(icon: Icons.search_off, title: context.tr('Tidak ada penyedia yang cocok'), detail: context.tr('Ubah kata kunci atau pilih kategori lain.')),
          for (final provider in _visibleProviders(context)) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.link_outlined, color: _mint),
                title: Text(provider.name),
                subtitle: Text('${_providerCategoryName(provider.category, context)} · ${context.tr('Belum terhubung')}\n${_providerDescription(provider, context)}'),
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
        _status = context.tr('Konfirmasikan izin untuk menguji endpoint ini.');
      });
      return;
    }
    final uri = _parseConnectionEndpoint(_endpointController.text.trim());
    if (uri == null) {
      setState(() {
        _reachable = false;
        _status = context.tr('Masukkan URL HTTPS valid tanpa kredensial, kueri, atau fragmen.');
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
            ? '${context.tr('Endpoint terjangkau')} (HTTP $code; ${context.tr('pengalihan tidak diikuti')})'
            : '${context.tr('Endpoint terjangkau')} (HTTP $code)';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = context.tr('Waktu habis saat menghubungi endpoint.');
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = context.tr('Endpoint tidak dapat dijangkau; periksa URL dan jaringan.');
      });
    } on HandshakeException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = context.tr('Validasi sertifikat TLS gagal.');
      });
    } on HttpException {
      if (!mounted) return;
      setState(() {
        _reachable = false;
        _status = context.tr('Permintaan HTTP gagal.');
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

String _categoryLabel(ToolCategory category, BuildContext context) => switch (category) {
      ToolCategory.webSecurity => context.tr('Keamanan web'),
      ToolCategory.networkSecurity => context.tr('Keamanan jaringan'),
      ToolCategory.analysis => context.tr('Analisis'),
    };

String _toolStatusLabel(ToolStatus status, BuildContext context) => switch (status) {
      ToolStatus.available => context.tr('Tersedia'),
      ToolStatus.notInstalled => context.tr('Belum terpasang'),
      ToolStatus.environmentRequired => context.tr('Memerlukan konfigurasi'),
      ToolStatus.limitedCompatibility => context.tr('Kompatibilitas terbatas'),
      ToolStatus.unsupported => context.tr('Tidak didukung'),
    };

String _providerCategoryName(ProviderCategory category, BuildContext context) => context.tr(providerCategoryLabel(category));

String _providerDescription(ProviderDefinition provider, BuildContext context) => switch (provider.id) {
      'openai' => context.tr('Penyedia AI opsional. Kunci dapat disimpan lokal, tetapi belum ada permintaan API.'),
      'gemini' => context.tr('Penyedia AI Google opsional. Kunci dapat disimpan lokal, tetapi belum ada permintaan API.'),
      'anthropic' => context.tr('Penyedia AI opsional. Kunci dapat disimpan lokal, tetapi belum ada permintaan API.'),
      'openrouter' => context.tr('Perute model AI opsional. Kunci dapat disimpan lokal, tetapi belum ada permintaan API.'),
      'cloudflare_workers' => context.tr('Backend edge milik pengguna. Uji ini hanya memeriksa keterjangkauan HTTPS.'),
      'firebase_auth' => context.tr('Autentikasi Firebase opsional. SDK Firebase belum dihubungkan.'),
      'firebase_functions' => context.tr('Cloud Functions milik pengguna. Pemanggilan fungsi belum diimplementasikan.'),
      'supabase' => context.tr('Database dan layanan Supabase milik pengguna. Akses terautentikasi belum tersedia.'),
      'cloudflare_d1' => context.tr('Database D1 sebaiknya diakses melalui Worker milik Anda; adapter belum tersedia.'),
      'cloudflare_r2' => context.tr('Penyimpanan objek R2 milik pengguna. Adapter unggah belum tersedia.'),
      'firebase_storage' => context.tr('Penyimpanan Firebase opsional. Unggah dan unduh belum tersedia.'),
      's3_compatible' => context.tr('Penyimpanan S3-compatible. Akses dan kredensial belum didukung.'),
      'webdav' => context.tr('Endpoint WebDAV HTTPS. Operasi terautentikasi belum didukung.'),
      'custom_rest' => context.tr('Endpoint HTTPS pilihan pengguna; hanya pemeriksaan koneksi tanpa autentikasi tersedia.'),
      _ => context.tr('Integrasi belum tersedia. Lihat panduan dan status sebelum memasukkan kredensial.'),
    };

String _toolDisplayDescription(String id, BuildContext context) => switch (id) {
      'dns_lookup' => context.tr('Mencari alamat IPv4 dan IPv6 domain melalui DNS perangkat.'),
      'tls_inspector' => context.tr('Memeriksa sertifikat TLS pada koneksi HTTPS port standar.'),
      'http_headers' => context.tr('Membaca header keamanan dari satu permintaan HTTPS ke halaman utama.'),
      'response_analyzer' => context.tr('Merangkum temuan dari pemeriksaan yang sudah dijalankan.'),
      _ => '',
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
        title: Text(dialogContext.tr('Simpan hasil ini ke perangkat?')),
        content: Text(dialogContext.tr('Target, detail respons, temuan, dan catatan konfirmasi izin akan disimpan dalam database SQLite privat aplikasi. Database tidak dienkripsi atau disinkronkan. Lanjutkan hanya jika penyimpanan ini sesuai untuk perangkat Anda.')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Batal'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Simpan lokal'))),
        ],
      ),
    );

Future<void> _confirmClearSavedResults(BuildContext context, Future<void> Function() onClear) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.tr('Hapus riwayat lokal?')),
      content: Text(dialogContext.tr('Tindakan ini menghapus permanen hasil tersimpan dari database privat aplikasi di perangkat ini.')),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Batal'))),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Hapus riwayat lokal'))),
      ],
    ),
  );
  if (confirmed == true) await onClear();
}

Future<void> _confirmClearResults(BuildContext context, VoidCallback onClear) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.tr('Hapus hasil sesi?')),
      content: Text(dialogContext.tr('Tindakan ini menghapus hasil sementara dari sesi ini. Laporan yang sudah disalin ke clipboard tidak ikut dihapus.')),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Batal'))),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Hapus hasil'))),
      ],
    ),
  );
  if (confirmed == true) onClear();
}

Future<void> _confirmCopyReport(BuildContext context, List<ToolRunResult> results) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.tr('Salin laporan sesi?')),
      content: Text(dialogContext.tr('Laporan memuat hostname, alamat IP, detail sertifikat, header respons, dan temuan. Data akan disalin ke clipboard sistem yang mungkin dapat dibaca aplikasi lain. Lanjutkan hanya jika Anda nyaman membagikan data ini.')),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Batal'))),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Salin laporan'))),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await Clipboard.setData(ClipboardData(text: buildSessionReportJson(results)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Laporan sesi disalin ke clipboard.'))));
    }
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Clipboard sistem tidak dapat diakses.'))));
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
      title: Text(_toolDisplayName(result.toolId, context)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${result.target} · ${result.completedAt.toLocal()}'),
            if (result.toolId != 'response_analyzer')
              Text('${context.tr('Konfirmasi izin diterima')}: ${result.authorizationConfirmed} (${context.tr('pernyataan mandiri saja')})'),
            const SizedBox(height: 8),
            Text(_displayResultSummary(result.summary, context), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final finding in result.findings) ...[
              const SizedBox(height: 10),
              Text('${_severityName(finding.severity, context)} · ${_displayFindingTitle(finding.title, context)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(_displayRecommendation(finding.recommendation, context)),
            ],
            if (result.details.isNotEmpty) ...[
              const Divider(height: 24),
              for (final detail in result.details)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: SelectableText(_displayResultDetail(detail, context))),
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Hasil lokal tidak dapat disimpan.'))));
              }
            },
            child: Text(context.tr('Simpan di perangkat')),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Tutup'))),
      ],
    ),
  );
}
