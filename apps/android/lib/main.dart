import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'core/local_result_store.dart';
import 'core/provider_registry.dart';
import 'core/report_exporter.dart';
import 'core/security_tools.dart';
import 'core/startup_trace.dart';
import 'core/tool_registry.dart';
import 'l10n/app_localizations.dart';
import 'widgets/animated_splash_screen.dart';
import 'widgets/assessment_runner.dart';
import 'widgets/provider_details_dialog.dart';
import 'widgets/release_catalog_dialog.dart';
import 'widgets/tool_runner_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTrace.begin();
  StartupTrace.mark('runApp-call');
  runApp(const CybersecurityAssistantApp());
}

const _ink = Color(0xFF0B1020);
const _panel = Color(0xFF151D31);
const _mint = Color(0xFF73F0C2);
const _electricBlue = Color(0xFF168DFF);

class CybersecurityAssistantApp extends StatefulWidget {
  const CybersecurityAssistantApp({super.key, this.resultStore});

  final ResultHistoryStore? resultStore;

  @override
  State<CybersecurityAssistantApp> createState() => _CybersecurityAssistantAppState();
}

class _CybersecurityAssistantAppState extends State<CybersecurityAssistantApp> {
  Locale _locale = const Locale('id');
  late final ResultHistoryStore _resultStore;
  bool _startupReady = false;
  bool _storeHandedToShell = false;

  @override
  void initState() {
    super.initState();
    StartupTrace.mark('flutter-root-init');
    _resultStore = widget.resultStore ?? LocalResultStore();
    // Render the branded Flutter handoff first; SQLite history is loaded by MainShell
    // after its first frame and must never gate the dashboard or native splash handoff.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      StartupTrace.mark('flutter-first-frame');
      _storeHandedToShell = true;
      setState(() => _startupReady = true);
    });
  }

  void _setLocale(Locale locale) => setState(() => _locale = locale);

  @override
  void dispose() {
    if (!_storeHandedToShell) unawaited(_resultStore.close());
    super.dispose();
  }

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
        ...GlobalMaterialLocalizations.delegates,
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
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 560),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(scale: Tween<double>(begin: .985, end: 1).animate(curved), child: child),
          );
        },
        child: _startupReady
            ? MainShell(
                key: const ValueKey('main-shell'),
                resultStore: _resultStore,
                locale: _locale,
                onLocaleChanged: _setLocale,
              )
            : const AnimatedSplashScreen(key: ValueKey('animated-splash')),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.resultStore,
    this.initialSavedResults,
    this.initialStorageError,
    this.locale = const Locale('id'),
    this.onLocaleChanged,
  });

  final ResultHistoryStore? resultStore;
  final List<ToolRunResult>? initialSavedResults;
  final String? initialStorageError;
  final Locale locale;
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
    StartupTrace.mark('dashboard-init');
    _resultStore = widget.resultStore ?? LocalResultStore();
    final startupResults = widget.initialSavedResults;
    if (startupResults != null) {
      _savedResults = List.unmodifiable(startupResults);
      _savedHistoryLoaded = true;
      _storageError = widget.initialStorageError;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      StartupTrace.mark('dashboard-first-frame');
      if (startupResults == null) unawaited(_loadSavedResults());
    });
  }

  void _selectDestination(int index) => setState(() => _selectedIndex = index);

  void _openConnections() {
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Connections and providers'))),
        body: const ConnectionsScreen(),
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ));
  }

  // AI remains a secondary screen; the centered bottom shortcut does not add a navigation destination.
  void _openAssistantModule() {
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => AssistantScreen(
        onOpenConnections: _openConnections,
        onOpenTools: () => _selectDestination(1),
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(.025, 0), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  void _rememberResult(ToolRunResult result) {
    setState(() {
      _recentResults.insert(0, result);
      if (_recentResults.length > 30) _recentResults.removeLast();
    });
  }

  void _clearResults() => setState(_recentResults.clear);

  Future<void> _loadSavedResults() async {
    StartupTrace.mark('sqlite-history-start');
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
      StartupTrace.mark('sqlite-history-loaded');
    } catch (_) {
      StartupTrace.mark('sqlite-history-error');
      if (mounted) setState(() => _storageError = 'Could not load local history on this device.');
    } finally {
      StartupTrace.mark('sqlite-history-finished');
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
    final wideLayout = MediaQuery.sizeOf(context).width >= 760;
    final recentResults = List<ToolRunResult>.unmodifiable(_recentResults);
    final savedResults = List<ToolRunResult>.unmodifiable(_savedResults);
    final destinations = <({String label, IconData icon})>[
      (label: context.tr('Home'), icon: Icons.home_rounded),
      (label: context.tr('Assessment'), icon: Icons.radar_rounded),
      (label: context.tr('Reports'), icon: Icons.article_outlined),
      (label: context.tr('Settings'), icon: Icons.settings_outlined),
    ];
    final pages = <Widget>[
      DashboardScreen(
        recentResults: recentResults,
        savedResultCount: _savedResults.length,
        savedHistoryLoaded: _savedHistoryLoaded,
        onNavigateToTools: () => _selectDestination(1),
        onNavigateToReports: () => _selectDestination(2),
        onOpenAssistant: _openAssistantModule,
        onSaveResult: _saveResultLocally,
      ),
      ToolsScreen(recentResults: recentResults, onResult: _rememberResult),
      ReportsScreen(
        recentResults: recentResults,
        savedResults: savedResults,
        savedHistoryLoaded: _savedHistoryLoaded,
        storageBusy: _storageBusy,
        storageError: _storageError,
        onLoadSavedResults: _loadSavedResults,
        onClearResults: _clearResults,
        onClearSavedResults: _clearSavedResults,
        onSaveResult: _saveResultLocally,
      ),
      SettingsScreen(
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
        onOpenAssistant: _openAssistantModule,
        onOpenConnections: _openConnections,
      ),
    ];
    final page = AnimatedSwitcher(
      duration: const Duration(milliseconds: 230),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .012), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_selectedIndex), child: pages[_selectedIndex]),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _ink,
        titleSpacing: 12,
        title: const Row(
          children: [
            Icon(Icons.shield_moon_outlined, color: _mint),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'CYBERSECURITY',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
        actions: const [Center(child: _ModeBadge()), SizedBox(width: 12)],
      ),
      body: SafeArea(
        child: Row(children: [
          if (wideLayout)
            NavigationRail(
              selectedIndex: _selectedIndex,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: _selectDestination,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(icon: Icon(destination.icon), label: Text(destination.label)),
              ],
            ),
          Expanded(child: page),
        ]),
      ),
      bottomNavigationBar: wideLayout
          ? null
          : _FloatingBottomNavigation(
              destinations: destinations,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              onOpenAssistant: _openAssistantModule,
            ),
    );
  }
}

class _FloatingBottomNavigation extends StatelessWidget {
  const _FloatingBottomNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenAssistant,
  });

  final List<({String label, IconData icon})> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xEB10192B),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .38), blurRadius: 20, offset: const Offset(0, 7))],
          ),
          child: Row(children: [
            Expanded(
              child: Row(children: [
                for (var index = 0; index < 2; index++)
                  Expanded(
                    child: _BottomNavItem(
                      key: ValueKey('bottom-navigation-$index'),
                      destination: destinations[index],
                      selected: selectedIndex == index,
                      onTap: () => onDestinationSelected(index),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 4),
            _AIChatNavButton(onTap: onOpenAssistant),
            const SizedBox(width: 4),
            Expanded(
              child: Row(children: [
                for (var index = 2; index < destinations.length; index++)
                  Expanded(
                    child: _BottomNavItem(
                      key: ValueKey('bottom-navigation-$index'),
                      destination: destinations[index],
                      selected: selectedIndex == index,
                      onTap: () => onDestinationSelected(index),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      );
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({String label, IconData icon}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: InkResponse(
          onTap: onTap,
          radius: 34,
          child: SizedBox(
            height: 68,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                height: 27,
                child: Center(
                  child: AnimatedScale(
                    scale: selected ? 1.12 : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : .72,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          boxShadow: selected
                              ? [BoxShadow(color: _electricBlue.withValues(alpha: .44), blurRadius: 14, spreadRadius: 1)]
                              : const [],
                        ),
                        child: Icon(destination.icon, size: 23, color: selected ? _electricBlue : const Color(0xFF8992A5)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      color: selected ? const Color(0xFFEAF5FF) : const Color(0xFF8992A5),
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: Text(destination.label, maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: selected ? 4 : 0,
                height: 4,
                decoration: BoxDecoration(
                  color: _electricBlue,
                  shape: BoxShape.circle,
                  boxShadow: selected ? [BoxShadow(color: _electricBlue.withValues(alpha: .8), blurRadius: 7)] : const [],
                ),
              ),
            ]),
          ),
        ),
      );
}

class _AIChatNavButton extends StatelessWidget {
  const _AIChatNavButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: context.tr('AI chat'),
        child: InkResponse(
          key: const ValueKey('bottom-navigation-ai-chat'),
          onTap: onTap,
          radius: 34,
          child: SizedBox(
            width: 54,
            height: 68,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF164A88), Color(0xFF07162D)]),
                  boxShadow: [
                    BoxShadow(color: _electricBlue.withValues(alpha: .36), blurRadius: 16, spreadRadius: 1),
                    const BoxShadow(color: Color(0x66168DFF), blurRadius: 3),
                  ],
                  border: Border.all(color: _electricBlue.withValues(alpha: .76), width: 1),
                ),
                child: const Icon(Icons.forum_rounded, size: 21, color: Color(0xFF8AD8FF)),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(context.tr('AI chat'), style: const TextStyle(color: Color(0xFFBBDFFF), fontSize: 9, fontWeight: FontWeight.w600, height: 1)),
              ),
            ]),
          ),
        ),
      );
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
    required this.savedResultCount,
    required this.savedHistoryLoaded,
    required this.onNavigateToTools,
    required this.onNavigateToReports,
    required this.onOpenAssistant,
    required this.onSaveResult,
  });

  final List<ToolRunResult> recentResults;
  final int savedResultCount;
  final bool savedHistoryLoaded;
  final VoidCallback onNavigateToTools;
  final VoidCallback onNavigateToReports;
  final VoidCallback onOpenAssistant;
  final Future<bool> Function(ToolRunResult) onSaveResult;

  @override
  Widget build(BuildContext context) {
    final availableTools = toolRegistry.where((tool) => tool.status == ToolStatus.available).length;
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Text(context.tr('Your security workspace'), style: _eyebrow(context)),
        const SizedBox(height: 8),
        Text(
          context.tr('Security, with control in your hands.'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.12),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('Checks run on your device. AI and cloud connections are optional.'),
          style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.5),
        ),
        const SizedBox(height: 20),
        _LocalFirstHero(onNavigateToTools: onNavigateToTools),
        const SizedBox(height: 18),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _DashboardMetric(
            icon: Icons.grid_view_rounded,
            value: '$availableTools',
            label: context.tr('Local tools'),
            onTap: onNavigateToTools,
          ),
          _DashboardMetric(
            icon: Icons.bolt_rounded,
            value: '${recentResults.length}',
            label: context.tr('Session checks'),
            onTap: onNavigateToReports,
          ),
          _DashboardMetric(
            icon: Icons.inventory_2_outlined,
            value: savedHistoryLoaded ? '$savedResultCount' : '…',
            label: context.tr('Saved locally'),
            onTap: onNavigateToReports,
          ),
        ]),
        const SizedBox(height: 24),
        _DashboardSectionHeader(
          title: context.tr('Recent activity'),
          icon: Icons.history_rounded,
          action: recentResults.isEmpty
              ? null
              : TextButton(onPressed: onNavigateToReports, child: Text(context.tr('View reports'))),
        ),
        const SizedBox(height: 10),
        if (recentResults.isEmpty)
          _EmptyState(
            icon: Icons.manage_search_rounded,
            title: context.tr('No checks yet'),
            detail: context.tr('Start an authorized check from the tool catalog. Results will appear here.'),
            action: TextButton.icon(
              onPressed: onNavigateToTools,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(context.tr('Browse local tools')),
            ),
          )
        else ...[
          for (final result in recentResults.take(3)) ...[
            _ResultCard(
              result: result,
              saved: false,
              onTap: () => _showResultDetails(context, result, onSaveResult: onSaveResult),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 18),
        _AssistantModuleCard(onOpen: onOpenAssistant),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.privacy_tip_outlined, color: _mint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('Only assess systems you own or have permission to test. App confirmation is not legal proof of authorization.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12, height: 1.45),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: content));
  }
}

class _LocalFirstHero extends StatelessWidget {
  const _LocalFirstHero({required this.onNavigateToTools});
  final VoidCallback onNavigateToTools;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D3157), Color(0xFF17233A), Color(0xFF142238)],
          ),
          border: Border.all(color: _mint.withValues(alpha: .18)),
        ),
        child: Stack(children: [
          Positioned(
            right: -12,
            top: -18,
            child: Icon(Icons.shield_outlined, size: 170, color: Colors.white.withValues(alpha: .035)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: _mint.withValues(alpha: .12), borderRadius: BorderRadius.circular(30)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check_circle_outline, size: 16, color: _mint),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .6),
                      child: Text(
                        context.tr('Local mode · Works offline'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _mint, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Text(context.tr('Your data. Your infrastructure.'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(context.tr('DNS lookup, TLS inspection, and HTTP security headers run locally on this device.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .76), height: 1.45)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onNavigateToTools,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(context.tr('Start a security check')),
              ),
            ]),
          ),
        ]),
      );
}

class _AssistantModuleCard extends StatelessWidget {
  const _AssistantModuleCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: const Color(0xFF8066FF).withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFAA9AFF)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('AI assistant module'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(context.tr('Not connected · local security tools remain available'),
                    style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 12)),
              ])),
              const Icon(Icons.arrow_forward_rounded),
            ]),
          ),
        ),
      );
}

class _ReportEntry {
  const _ReportEntry({required this.result, required this.saved});
  final ToolRunResult result;
  final bool saved;
}

enum _ReportFilter { all, session, saved }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.recentResults,
    required this.savedResults,
    required this.savedHistoryLoaded,
    required this.storageBusy,
    required this.storageError,
    required this.onLoadSavedResults,
    required this.onClearResults,
    required this.onClearSavedResults,
    required this.onSaveResult,
  });

  final List<ToolRunResult> recentResults;
  final List<ToolRunResult> savedResults;
  final bool savedHistoryLoaded;
  final bool storageBusy;
  final String? storageError;
  final Future<void> Function() onLoadSavedResults;
  final VoidCallback onClearResults;
  final Future<void> Function() onClearSavedResults;
  final Future<bool> Function(ToolRunResult) onSaveResult;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportFilter _filter = _ReportFilter.all;

  @override
  Widget build(BuildContext context) {
    final rows = <_ReportEntry>[
      if (_filter != _ReportFilter.saved) for (final result in widget.recentResults) _ReportEntry(result: result, saved: false),
      if (_filter != _ReportFilter.session) for (final result in widget.savedResults) _ReportEntry(result: result, saved: true),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), children: [
          Text(context.tr('REPORTS'), style: _eyebrow(context)),
          const SizedBox(height: 8),
          Text(context.tr('Reports and history'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(context.tr('Review current session checks and results saved in private on-device SQLite.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .7), height: 1.45)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final filter in _ReportFilter.values)
              ChoiceChip(
                label: Text(context.tr(switch (filter) {
                  _ReportFilter.all => 'All reports',
                  _ReportFilter.session => 'This session',
                  _ReportFilter.saved => 'Saved on device',
                })),
                selected: filter == _filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ]),
          const SizedBox(height: 12),
          if (_filter != _ReportFilter.saved && widget.recentResults.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _confirmCopyReport(context, widget.recentResults),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(context.tr('Export session JSON')),
              ),
              TextButton.icon(
                onPressed: () => _confirmClearResults(context, widget.onClearResults),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.tr('Clear session')),
              ),
            ]),
          if (_filter != _ReportFilter.session)
            Row(children: [
              Expanded(
                child: Text(context.tr('Stored locally in app-private SQLite. Not encrypted or synced.'),
                    style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 12, height: 1.4)),
              ),
              if (widget.savedHistoryLoaded && widget.savedResults.isNotEmpty)
                IconButton(
                  tooltip: context.tr('Delete saved history'),
                  onPressed: widget.storageBusy ? null : () => _confirmClearSavedResults(context, widget.onClearSavedResults),
                  icon: const Icon(Icons.delete_outline),
                ),
              IconButton(
                tooltip: context.tr('Refresh history'),
                onPressed: widget.storageBusy ? null : () => widget.onLoadSavedResults(),
                icon: widget.storageBusy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
            ]),
          if (widget.storageError != null) ...[
            const SizedBox(height: 8),
            Text(_translateStorageError(context, widget.storageError!), style: const TextStyle(color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 8),
          if (widget.storageBusy && rows.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            _EmptyState(
              icon: Icons.article_outlined,
              title: context.tr('No reports in this view'),
              detail: context.tr('Run a local check, or save a result from its details to keep it after closing the app.'),
            )
          else
            for (final entry in rows) ...[
              _ResultCard(
                result: entry.result,
                saved: entry.saved,
                onTap: () => _showResultDetails(
                  context,
                  entry.result,
                  onSaveResult: entry.saved ? null : widget.onSaveResult,
                ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 16),
          Text(context.tr('Only assess systems you own or have permission to test. App confirmation is not legal proof of authorization.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 12, height: 1.45)),
        ]),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.saved, required this.onTap});
  final ToolRunResult result;
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: _mint.withValues(alpha: .1), borderRadius: BorderRadius.circular(13)),
                child: Icon(saved ? Icons.bookmark_outline_rounded : _toolIcon(result.toolId), color: _mint),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_toolDisplayName(result.toolId, context), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('${result.target} · ${_displayResultSummary(result.summary, context)}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12)),
                const SizedBox(height: 3),
                Text(saved ? context.tr('Saved report') : context.tr('Session result'),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
              ])),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required this.onOpenAssistant,
    required this.onOpenConnections,
  });

  final Locale locale;
  final ValueChanged<Locale>? onLocaleChanged;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenConnections;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), children: [
            Text(context.tr('SETTINGS'), style: _eyebrow(context)),
            const SizedBox(height: 8),
            Text(context.tr('Preferences and privacy'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.language_rounded, color: _mint),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.tr('Interface language'), style: const TextStyle(fontWeight: FontWeight.w600))),
                  DropdownButton<Locale>(
                    value: locale,
                    underline: const SizedBox.shrink(),
                    onChanged: onLocaleChanged == null
                        ? null
                        : (selected) {
                            if (selected != null) onLocaleChanged!(selected);
                          },
                    items: [
                      DropdownMenuItem(value: const Locale('id'), child: Text(context.tr('Bahasa Indonesia'))),
                      DropdownMenuItem(value: const Locale('en'), child: Text(context.tr('English'))),
                    ],
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFAA9AFF)),
                title: Text(context.tr('AI & models')),
                subtitle: Text(context.tr('Assistant is not connected. The module opens as a secondary screen, outside primary navigation.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenAssistant,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.hub_outlined, color: _mint),
                title: Text(context.tr('Connections and providers')),
                subtitle: Text(context.tr('Manage your optional endpoints and review provider guides.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenConnections,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lock_outline_rounded, color: _mint),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr('Privacy and local storage'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(context.tr('Built-in checks run on this device. Saved reports use app-private SQLite and are not encrypted or synced.'),
                        style: TextStyle(color: Colors.white.withValues(alpha: .68), height: 1.45)),
                  ])),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({required this.icon, required this.value, required this.label, required this.onTap});
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(icon, color: _mint),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(value, key: ValueKey(value), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12)),
                ])),
              ]),
            ),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Text(context.tr('SECURITY ASSESSMENT'), style: _eyebrow(context)),
            const SizedBox(height: 8),
            Text(context.tr('Pemeriksaan keamanan'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(context.tr('Alat bawaan berjalan di perangkat. Pemeriksaan jaringan memerlukan target dan konfirmasi izin.'),
                style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.45)),
            const SizedBox(height: 14),
            AssessmentRunner(onResult: widget.onResult),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Text(context.tr('TOOL REGISTRY'), style: _eyebrow(context)),
            const SizedBox(height: 8),
            Text(context.tr('KATALOG ALAT'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showReleaseCatalog(context),
                icon: const Icon(Icons.code_rounded),
                label: Text(context.tr('Lihat rilis GitHub')),
              ),
            ),
            const SizedBox(height: 8),
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
              for (final category in toolRegistry.map((tool) => tool.category).toSet())
                FilterChip(
                  label: Text(_categoryLabel(category, context)),
                  selected: _selectedCategory == category,
                  onSelected: (selected) => setState(() => _selectedCategory = selected ? category : null),
                ),
            ]),
            const SizedBox(height: 8),
            if (filteredTools.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Center(child: Text(context.tr('Tidak ada alat yang cocok dengan pencarian.'))),
              )
            else
              for (final tool in filteredTools) ...[
                Card(
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
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key, required this.onOpenConnections, required this.onOpenTools});

  final VoidCallback onOpenConnections;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('AI assistant module'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(context.tr('AI ASSISTANT'), style: _eyebrow(context)),
              const SizedBox(height: 8),
              Text(context.tr('AI assistance'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, color: _mint, size: 28),
                    const SizedBox(height: 12),
                    Text(context.tr('AI assistant is not connected'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(context.tr('No messages are sent to an AI provider. Provider connections and AI analysis are not implemented. Do not enter API keys or sensitive data on this screen.'),
                        style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.5)),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onOpenConnections();
                        },
                        icon: const Icon(Icons.hub_outlined),
                        label: Text(context.tr('View connection center')),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onOpenTools();
                        },
                        icon: const Icon(Icons.grid_view_rounded),
                        label: Text(context.tr('Use local tools')),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
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
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
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
                leading: _ProviderBrandMark(provider: provider),
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
          ),
        ),
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

class _ProviderBrandMark extends StatelessWidget {
  const _ProviderBrandMark({required this.provider});

  final ProviderDefinition provider;

  @override
  Widget build(BuildContext context) {
    final (icon, color, mark) = switch (provider.id) {
      'cloudflare_workers' || 'cloudflare_d1' || 'cloudflare_r2' => (Icons.cloud_rounded, const Color(0xFFF38020), 'CF'),
      'firebase_auth' || 'firebase_functions' || 'firebase_firestore' || 'firebase_storage' =>
        (Icons.local_fire_department_rounded, const Color(0xFFFFB300), 'F'),
      'supabase' => (Icons.storage_rounded, const Color(0xFF3ECF8E), 'S'),
      'openai' => (Icons.auto_awesome_rounded, const Color(0xFF10A37F), 'OAI'),
      'gemini' => (Icons.auto_awesome_rounded, const Color(0xFF4285F4), 'G'),
      'anthropic' => (Icons.text_fields_rounded, const Color(0xFFD97757), 'A'),
      'openrouter' => (Icons.alt_route_rounded, const Color(0xFF8B78E6), 'OR'),
      'virustotal' => (Icons.shield_rounded, const Color(0xFF536DFF), 'VT'),
      'shodan' => (Icons.radar, const Color(0xFFE44B5F), 'S'),
      'urlscan' => (Icons.travel_explore, const Color(0xFF28B8CC), 'U'),
      's3_compatible' => (Icons.cloud_queue_rounded, const Color(0xFFF59D28), 'S3'),
      'webdav' => (Icons.folder_open_rounded, const Color(0xFF28B8CC), 'W'),
      _ => switch (provider.category) {
          ProviderCategory.backend => (Icons.cloud_outlined, const Color(0xFF7BA8E8), 'API'),
          ProviderCategory.database => (Icons.storage_rounded, const Color(0xFF5BC0BE), 'DB'),
          ProviderCategory.storage => (Icons.folder_open_rounded, const Color(0xFF6EB6D8), 'IO'),
          ProviderCategory.ai => (Icons.auto_awesome_rounded, const Color(0xFF9A8BFF), 'AI'),
          ProviderCategory.securityIntelligence => (Icons.security_rounded, const Color(0xFF65A9FF), 'SEC'),
          ProviderCategory.custom => (Icons.api, const Color(0xFFAAB4C5), 'API'),
        },
    };

    return Semantics(
      label: '${provider.name} icon',
      image: true,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: mark.length > 1
            ? Text(mark, style: TextStyle(color: color, fontSize: mark.length > 2 ? 9 : 12, fontWeight: FontWeight.w800, letterSpacing: -.3))
            : Icon(icon, color: color, size: 22),
      ),
    );
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
      ToolCategory.webSecurity => context.tr('Web Security'),
      ToolCategory.networkSecurity => context.tr('Network Security'),
      ToolCategory.osint => context.tr('OSINT'),
      ToolCategory.apkMobileSecurity => context.tr('APK / Mobile Security'),
      ToolCategory.codeSecurity => context.tr('Code Security'),
      ToolCategory.cloudSecurity => context.tr('Cloud Security'),
      ToolCategory.vulnerabilityAssessment => context.tr('Vulnerability Assessment'),
      ToolCategory.malwareAnalysis => context.tr('Malware Analysis'),
      ToolCategory.threatIntelligence => context.tr('Threat Intelligence'),
      ToolCategory.digitalForensics => context.tr('Digital Forensics'),
      ToolCategory.analysis => context.tr('Analysis'),
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
      'dns_lookup' => context.tr('Mencari alamat IPv4 dan IPv6 melalui resolver sistem Android; CNAME dan record lain belum tersedia.'),
      'tls_inspector' => context.tr('Memvalidasi koneksi TLS dan memeriksa identitas serta masa berlaku sertifikat.'),
      'http_headers' => context.tr('Mengirim satu GET HTTPS terbatas ke path yang dipilih dan memeriksa header serta body respons.'),
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
              Text('${context.tr(finding.confidence.name).toUpperCase()} · ${_severityName(finding.severity, context)} · ${_displayFindingTitle(finding.title, context)}', style: const TextStyle(fontWeight: FontWeight.w600)),
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
