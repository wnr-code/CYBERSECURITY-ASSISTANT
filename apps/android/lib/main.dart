import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'core/activity_timeline.dart';
import 'core/apk_integrity.dart';
import 'core/ai_assistant_coordinator.dart';
import 'core/ai_provider_manager.dart';
import 'core/ai_terminal_execution_bridge.dart';
import 'core/assessment_execution_manager.dart';
import 'core/diagnostics.dart';
import 'core/local_result_store.dart';
import 'core/market_provider_manager.dart';
import 'core/package_manager.dart';
import 'core/provider_registry.dart';
import 'core/report_exporter.dart';
import 'core/runtime_manager.dart';
import 'core/security_findings.dart';
import 'core/secure_credential_store.dart';
import 'core/security_tools.dart';
import 'core/startup_trace.dart';
import 'core/terminal_process_executor.dart';
import 'core/terminal_runtime_adapter.dart';
import 'core/terminal_session_manager.dart';
import 'core/tool_orchestrator.dart';
import 'core/tool_registry.dart';
import 'core/workspace_file_system.dart';
import 'l10n/activity_localization.dart';
import 'l10n/app_localizations.dart';
import 'widgets/animated_splash_screen.dart';
import 'widgets/diagnostics_screen.dart';
import 'widgets/edge_panel.dart';
import 'widgets/floating_terminal.dart';
import 'widgets/assistant_screen.dart';
import 'widgets/assessment_runner.dart';
import 'widgets/catalog_screen.dart';
import 'widgets/dashboard_screen.dart';
import 'widgets/market_screen.dart';
import 'widgets/market_provider_detail_screen.dart';
import 'widgets/cloudflare_dashboard_screen.dart';
import 'widgets/security_overview_screen.dart';
import 'widgets/provider_details_dialog.dart';
import 'widgets/release_catalog_dialog.dart';
import 'widgets/tool_runner_dialog.dart';

final DiagnosticReporter _diagnostics = DiagnosticReporter(store: FileDiagnosticQueueStore());

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTrace.begin();
  final apkIntegrity = await ApkIntegrityMonitor(
    nativeBridge: const MethodChannelAppIntegrityBridge(),
    secureStorage: FlutterSecureStorageBackend(),
  ).verifyAtStartup(enforceRelease: kReleaseMode);
  final mustBlockRelease = kReleaseMode && !apkIntegrity.trusted;
  if (!mustBlockRelease) {
    DiagnosticHooks.install(_diagnostics);
    _diagnostics.startRetryLoop();
    unawaited(_initializeDiagnostics());
  }
  StartupTrace.mark('runApp-call');
  runApp(CybersecurityAssistantApp(apkIntegrityReport: apkIntegrity));
}

Future<void> _initializeDiagnostics() async {
  try {
    await _diagnostics.initialize();
    const appVersion = '0.1.0'; // Keep aligned with pubspec.yaml.
    const buildNumber = '1'; // Keep aligned with pubspec.yaml's +build suffix.
    var android = 'Android';
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      android = 'Android ${info.version.release} (API ${info.version.sdkInt})';
    }
    _diagnostics.updateDeviceMetadata(appVersion: appVersion, buildNumber: buildNumber, androidVersion: android);
    final crashFile = File('${(await getApplicationSupportDirectory()).path}/pending_native_crash.txt');
    await consumeNativeCrashFile(_diagnostics, crashFile);
    Connectivity().checkConnectivity().then((results) {
      // Connectivity is only a coarse transport hint, not proof of internet reachability.
      _diagnostics.setWifiAvailability(results.contains(ConnectivityResult.wifi));
    }).catchError((_) {});
    Connectivity().onConnectivityChanged.listen((results) {
      _diagnostics.setWifiAvailability(results.contains(ConnectivityResult.wifi));
    });
  } catch (error, stack) {
    await _diagnostics.record(error, stackTrace: stack, category: DiagnosticCategory.startup);
  }
}

const _ink = Color(0xFF0B1020);
const _panel = Color(0xFF151D31);
const _mint = Color(0xFF73F0C2);
const _electricBlue = Color(0xFF168DFF);

class CybersecurityAssistantApp extends StatefulWidget {
  const CybersecurityAssistantApp({super.key, this.resultStore, this.apkIntegrityReport});

  final ResultHistoryStore? resultStore;
  final ApkIntegrityReport? apkIntegrityReport;

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
    if (kReleaseMode && widget.apkIntegrityReport?.trusted != true) return;
    // Hold the branded Flutter handoff long enough to be visible on real phones.
    // The native Android splash covers engine startup; neither splash waits for SQLite.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      StartupTrace.mark('flutter-first-frame');
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
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
      home: kReleaseMode && widget.apkIntegrityReport?.trusted != true
          ? _AppIntegrityBlockedScreen(report: widget.apkIntegrityReport)
          : AnimatedSwitcher(
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
                apkIntegrityReport: widget.apkIntegrityReport,
                locale: _locale,
                onLocaleChanged: _setLocale,
              )
            : const AnimatedSplashScreen(key: ValueKey('animated-splash')),
      ),
    );
  }
}

class _AppIntegrityBlockedScreen extends StatelessWidget {
  const _AppIntegrityBlockedScreen({required this.report});
  final ApkIntegrityReport? report;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _ink,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.gpp_bad_outlined, color: Colors.orangeAccent, size: 42),
                    const SizedBox(height: 14),
                    Text(context.tr('Application integrity check failed'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(context.tr('The app cannot open because its trusted identity or update could not be verified.'), style: const TextStyle(height: 1.45)),
                    if (report != null) ...[
                      const SizedBox(height: 12),
                      Text(context.tr(report!.message), style: TextStyle(color: Colors.white.withValues(alpha: .66), height: 1.4)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.resultStore,
    this.apkIntegrityReport,
    this.activityStore,
    this.findingRepository,
    this.assessmentExecutionManager,
    this.marketProviderManager,
    this.aiProviderManager,
    this.initialSavedResults,
    this.initialStorageError,
    this.locale = const Locale('id'),
    this.onLocaleChanged,
  });

  final ResultHistoryStore? resultStore;
  final ApkIntegrityReport? apkIntegrityReport;
  final ActivityHistoryStore? activityStore;
  final FindingRepository? findingRepository;
  final AssessmentExecutionManager? assessmentExecutionManager;
  final MarketProviderManager? marketProviderManager;
  final AiProviderManager? aiProviderManager;
  final List<ToolRunResult>? initialSavedResults;
  final String? initialStorageError;
  final Locale locale;
  final ValueChanged<Locale>? onLocaleChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _openFindingsOnReports = false;
  FindingSeverity? _openFindingsSeverity;
  final List<ToolRunResult> _recentResults = [];
  late final ResultHistoryStore _resultStore;
  late final ActivityHistoryStore _activityStore;
  late final FindingRepository _findingRepository;
  late final MarketPackageManager _marketPackageManager;
  late final AssessmentExecutionManager _assessmentExecutionManager;
  late final AiProviderManager _aiProviderManager;
  late final MarketProviderManager _marketProviderManager;
  late final bool _ownsAiProviderManager;
  late final bool _ownsMarketProviderManager;
  late final ToolOrchestrator _terminalOrchestrator;
  late final TerminalSessionManager _terminalSession;
  late final SafeTerminalProcessExecutor _terminalExecutor;
  final ValueNotifier<int> _securityOverviewChanges = ValueNotifier<int>(0);
  bool _edgePanelOpen = false;
  bool _terminalOpen = false;
  bool _terminalMinimized = false;
  Offset? _terminalPosition;
  List<FindingRecord> _findings = [];
  bool _findingsLoaded = false;
  bool _findingsBusy = false;
  String? _findingsError;
  List<ActivityEvent> _activityEvents = [];
  bool _activityHistoryLoaded = false;
  bool _activityBusy = false;
  String? _activityError;
  List<ToolRunResult> _savedResults = [];
  bool _savedHistoryLoaded = false;
  bool _storageBusy = false;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    StartupTrace.mark('dashboard-init');
    _resultStore = widget.resultStore ?? LocalResultStore();
    _activityStore = widget.activityStore ??
        (_resultStore is ActivityHistoryStore ? _resultStore as ActivityHistoryStore : MemoryActivityHistoryStore());
    _findingRepository = widget.findingRepository ??
        (_resultStore is FindingRepository ? _resultStore as FindingRepository : MemoryFindingRepository());
    final secureBackend = FlutterSecureStorageBackend();
    final credentials = SecureCredentialStore(backend: secureBackend);
    _ownsAiProviderManager = widget.aiProviderManager == null && widget.marketProviderManager == null;
    _aiProviderManager = widget.aiProviderManager ?? widget.marketProviderManager?.aiProviders ?? AiProviderManager(
      credentialStore: credentials,
      adapters: [GeminiAiProviderAdapter(credentialStore: credentials)],
    );
    _ownsMarketProviderManager = widget.marketProviderManager == null;
    _marketProviderManager = widget.marketProviderManager ?? MarketProviderManager(
      credentials: credentials,
      configuration: ProviderConfigurationStore(secureBackend),
      aiProviders: _aiProviderManager,
      activityStore: _activityStore,
      onActivity: _acceptActivity,
    );
    _marketPackageManager = MarketPackageManager.bundled();
    _terminalOrchestrator = ToolOrchestrator(
      packageManager: _marketPackageManager,
      activityStore: _activityStore,
      findingRepository: _findingRepository,
      reportStore: _resultStore,
      onActivity: _acceptActivity,
      onFindings: _acceptFindings,
      onReportSaved: _acceptSavedReport,
      onReportSaveFailed: _reportSaveFailed,
    );
    _terminalSession = TerminalSessionManager(activityStore: _activityStore, onActivity: _acceptActivity);
    _terminalExecutor = SafeTerminalProcessExecutor(
      runtimeAdapter: TerminalRuntimeAdapter(orchestrator: _terminalOrchestrator, runAfterConsent: _runTerminalTool),
      workspaceProvider: () => WorkspaceFileSystem.forApplication(authorize: _authorizeWorkspaceOperation),
    );
    _assessmentExecutionManager = widget.assessmentExecutionManager ?? AssessmentExecutionManager(
      orchestrator: ToolOrchestrator(
        packageManager: _marketPackageManager,
        activityStore: _activityStore,
        onActivity: _acceptActivity,
        findingRepository: _findingRepository,
        onFindings: _acceptFindings,
        onReportSaved: _acceptSavedReport,
        onReportSaveFailed: _reportSaveFailed,
      ),
      onResult: (result) {
        if (mounted) _rememberResult(result);
      },
    );
    _assessmentExecutionManager.addListener(_assessmentExecutionChanged);
    unawaited(_synchronizeMarketRuntimeAvailability());
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
      unawaited(_loadActivityEvents());
      unawaited(_loadFindings());
    });
  }

  void _selectDestination(int index) => setState(() {
        _selectedIndex = index;
        _edgePanelOpen = false;
        _openFindingsOnReports = false;
        _openFindingsSeverity = null;
      });

  void _navigateToFindings(FindingSeverity? severity) => setState(() {
        _selectedIndex = 2;
        _edgePanelOpen = false;
        _openFindingsOnReports = true;
        _openFindingsSeverity = severity;
      });

  void _openSecurityOverview() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 230),
      reverseTransitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => AnimatedBuilder(
        animation: Listenable.merge([_assessmentExecutionManager, _securityOverviewChanges]),
        builder: (context, _) => SecurityOverviewScreen(
          assessmentProgress: _assessmentExecutionManager.progress,
          activeAssessmentTarget: _assessmentExecutionManager.activeRun == null
              ? null
              : sanitizeActivityTarget(_assessmentExecutionManager.activeRun!.target),
          latestAssessment: _latestAssessmentEvent,
          findings: List.unmodifiable(_findings),
          findingsLoaded: _findingsLoaded,
          findingsBusy: _findingsBusy,
          findingsError: _findingsError,
          activityEvents: List.unmodifiable(_activityEvents),
          activityLoaded: _activityHistoryLoaded,
          activityBusy: _activityBusy,
          activityError: _activityError,
          onOpenAssessment: () {
            Navigator.of(context).pop();
            _selectDestination(1);
          },
          onOpenFindings: (severity) {
            Navigator.of(context).pop();
            _navigateToFindings(severity);
          },
          onOpenReports: () {
            Navigator.of(context).pop();
            _selectDestination(2);
          },
          onOpenActivity: (event) {
            Navigator.of(context).pop();
            unawaited(_openActivitySource(event));
          },
        ),
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, .025), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  ActivityEvent? get _latestAssessmentEvent {
    final assessments = _activityEvents.where((event) => event.kind == ActivityKind.assessment).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return assessments.isEmpty ? null : assessments.first;
  }

  void _assessmentExecutionChanged() {
    if (mounted) setState(() {});
  }

  void _notifySecurityOverview() {
    if (mounted) _securityOverviewChanges.value++;
  }

  Future<bool> _reviewAiTool(AiTerminalToolProposal proposal) async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Review AI tool proposal')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${dialogContext.tr('Tool')}: ${proposal.toolId}'),
          const SizedBox(height: 6),
          Text('${dialogContext.tr('Target')}: ${proposal.target}'),
          const SizedBox(height: 8),
          Text('${dialogContext.tr('Reason')}: ${proposal.rationale}'),
          const SizedBox(height: 10),
          Text(dialogContext.tr('This is only the first review. The tool runner will separately validate target scope and require its authorization confirmation before network access.')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Decline'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Review tool'))),
        ],
      ),
    );
    return approved == true;
  }

  TerminalExecutionResult _assistantToolReceipt(ToolRunResult result) {
    final report = result.runtimeExecutionReport;
    final runtimeReport = report is RuntimeExecutionReport ? report : null;
    return TerminalExecutionResult.completed(
      _displayResultSummary(result.summary, context),
      executionId: runtimeReport?.executionId,
      executionData: {
        'tool_id': result.toolId,
        'target': result.target,
        'summary': result.summary,
        'details': result.details.take(12).toList(growable: false),
        'findings': result.findings.take(12).map((finding) => {
          'title': finding.title,
          'severity': finding.severity.name,
          'confidence': finding.confidence.name,
          'recommendation': finding.recommendation,
        }).toList(growable: false),
        'runtime_status': runtimeReport?.outcome.name,
        'authorization_confirmed': result.authorizationConfirmed,
        'completed_at': result.completedAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<bool> _authorizeWorkspaceOperation({
    required WorkspaceActor actor,
    required WorkspaceAction action,
    required String relativePath,
  }) async {
    if (!mounted || actor != WorkspaceActor.terminal) return false;
    final prompt = switch (action) {
      WorkspaceAction.list => 'Allow Terminal to list this workspace path?',
      WorkspaceAction.read => 'Allow Terminal to read this workspace file?',
      WorkspaceAction.write => 'Allow Terminal to write this workspace file?',
      WorkspaceAction.createDirectory => 'Allow Terminal to create this workspace directory?',
      WorkspaceAction.delete => 'Allow Terminal to delete this workspace file?',
    };
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.tr('Workspace access request')),
            content: Text('${dialogContext.tr(prompt)}\n\n${dialogContext.tr('Only this workspace-relative path is in scope:')} $relativePath\n\n${dialogContext.tr('Private app data, credentials, executables, and app code are excluded.')}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(dialogContext.tr('Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(dialogContext.tr('Allow once'))),
            ],
          ),
        ) ??
        false;
  }

  Future<TerminalExecutionResult?> _runTerminalTool(String toolId, String? target, {String? correlationId}) async {
    final definition = _terminalOrchestrator.registry.byId(toolId);
    if (definition == null || !mounted) return null;
    ToolRunResult? completedResult;
    TerminalExecutionResult? executionOutcome;
    final dialogResult = await showDialog<ToolRunResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ToolRunnerDialog(
        tool: definition,
        recentResults: List.unmodifiable([..._recentResults, ..._savedResults]),
        initialTarget: target,
        correlationId: correlationId,
        orchestrator: _terminalOrchestrator,
        onExecutionFinished: (result, cancelled) {
          completedResult = result;
          executionOutcome = result != null
              ? _assistantToolReceipt(result)
              : cancelled
                  ? TerminalExecutionResult.cancelled(context.tr('Check cancelled.'))
                  : TerminalExecutionResult.failed(context.tr('The tool did not complete. Review Reports or the Activity Timeline.'));
        },
      ),
    );
    final result = dialogResult ?? completedResult;
    if (result != null && mounted) {
      _rememberResult(result);
      return _assistantToolReceipt(result);
    }
    return executionOutcome;
  }

  void _openTerminalWorkspace() {
    if (_terminalSession.isExited) _terminalSession.startNewSession();
    setState(() {
      _edgePanelOpen = false;
      _terminalOpen = true;
      _terminalMinimized = false;
      _terminalPosition = null;
    });
  }

  void _closeTerminalWorkspace() => setState(() {
        _terminalOpen = false;
        _terminalMinimized = false;
        _terminalPosition = null;
      });

  Future<void> _exitMinimizedTerminal() async {
    if (_terminalSession.status == TerminalSessionStatus.running) return;
    await _terminalSession.exit();
    if (mounted) _closeTerminalWorkspace();
  }

  void _moveTerminal(Offset delta, Size bounds, Size panelSize) {
    final current = _terminalPosition ?? Offset(
      math.max(8.0, bounds.width - panelSize.width - 12).toDouble(),
      math.max(8.0, bounds.height - panelSize.height - 12).toDouble(),
    );
    setState(() {
      _terminalPosition = Offset(
        (current.dx + delta.dx).clamp(0.0, math.max(0.0, bounds.width - panelSize.width)).toDouble(),
        (current.dy + delta.dy).clamp(0.0, math.max(0.0, bounds.height - panelSize.height)).toDouble(),
      );
    });
  }

  void _openConnections({ProviderCategory? initialCategory}) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      reverseTransitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Connections and providers'))),
        body: ConnectionsScreen(initialCategory: initialCategory),
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ));
  }

  void _openMarket() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      reverseTransitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => MarketScreen(
        packageManager: _marketPackageManager,
        providerManager: _marketProviderManager,
        onOpenCloudflareDashboard: _openCloudflareDashboard,
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ));
  }

  void _openCatalog() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      reverseTransitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => CatalogScreen(
        packageManager: _marketPackageManager,
        providerManager: _marketProviderManager,
        onOpenAssessment: () => _selectDestination(1),
        onOpenCloudflareDashboard: _openCloudflareDashboard,
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ));
  }

  void _openCloudflareDashboard() {
    if (_marketProviderManager.statusFor('cloudflare') != ManagedProviderStatus.connected) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Verify and connect the Cloudflare token from Market first.'))));
      return;
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      reverseTransitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => CloudflareDashboardScreen(
        manager: _marketProviderManager,
        onOpenTerminal: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          _openTerminalWorkspace();
        },
      ),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ));
  }

  void _openGeminiProviderDetails() {
    if (_marketProviderManager.statusFor('gemini') != ManagedProviderStatus.connected) return;
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => MarketProviderDetailScreen(providerId: 'gemini', manager: _marketProviderManager),
    ));
  }

  void _openDiagnostics() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      reverseTransitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => DiagnosticsScreen(reporter: _diagnostics, marketManager: _marketPackageManager, apkIntegrityReport: widget.apkIntegrityReport),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ));
  }

  // AI remains a secondary screen; the centered bottom shortcut does not add a navigation destination.
  void _openAssistantModule() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      transitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      reverseTransitionDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        final coordinator = AiAssistantCoordinator(
          providers: _aiProviderManager,
          bridge: AiTerminalExecutionBridge(runtime: _terminalExecutor.runtimeAdapter),
          activityStore: _activityStore,
        );
        return AssistantScreen(
          providers: _aiProviderManager,
          coordinator: coordinator,
          reviewTool: _reviewAiTool,
          onOpenConnections: () => _openConnections(initialCategory: ProviderCategory.ai),
          onOpenTools: () => _selectDestination(1),
        );
      },
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
      final reportId = activityResultKey(result.toolId, result.target, result.completedAt);
      _recentResults.removeWhere((item) => activityResultKey(item.toolId, item.target, item.completedAt) == reportId);
      _recentResults.insert(0, result);
      if (_recentResults.length > 30) _recentResults.removeLast();
    });
  }

  void _acceptSavedReport(ToolRunResult result) {
    if (!mounted) return;
    final reportId = activityResultKey(result.toolId, result.target, result.completedAt);
    setState(() {
      _savedResults.removeWhere((item) => activityResultKey(item.toolId, item.target, item.completedAt) == reportId);
      _savedResults.insert(0, result);
      if (_savedResults.length > 500) _savedResults.removeRange(500, _savedResults.length);
      _storageError = null;
    });
  }

  void _reportSaveFailed(Object _, StackTrace __) {
    if (!mounted) return;
    setState(() => _storageError = 'Could not save the result to local history.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Could not save the result locally.'))));
  }

  Future<void> _openActivitySource(ActivityEvent event) async {
    ToolRunResult? sourceResult;
    final sourceKey = event.sourceResultKey;
    if (sourceKey != null) {
      final inMemory = [..._recentResults, ..._savedResults];
      for (final result in inMemory) {
        if (activityResultKey(result.toolId, result.target, result.completedAt) == sourceKey) {
          sourceResult = result;
          break;
        }
      }
      if (sourceResult == null) {
        try {
          sourceResult = await _resultStore.loadReportById(sourceKey);
        } catch (error, stack) {
          DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
        }
      }
    }
    if (!mounted) return;
    final openSource = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Activity details')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ActivityDetailLine(label: dialogContext.tr('Activity type'), value: event.kind == ActivityKind.assessment
              ? dialogContext.tr('Assessment run')
              : event.kind == ActivityKind.aiRequest
                  ? dialogContext.tr('AI request')
                  : _toolDisplayName(event.toolId ?? '', dialogContext)),
          _ActivityDetailLine(label: dialogContext.tr('Activity ID'), value: event.eventId),
          _ActivityDetailLine(label: dialogContext.tr('Target'), value: event.target),
          _ActivityDetailLine(label: dialogContext.tr('Status'), value: _activityStatusLabel(event.status, dialogContext)),
          _ActivityDetailLine(label: dialogContext.tr('Started'), value: event.startedAt.toLocal().toString()),
          if (event.finishedAt != null) _ActivityDetailLine(label: dialogContext.tr('Finished'), value: event.finishedAt!.toLocal().toString()),
          if (event.summary != null) _ActivityDetailLine(label: dialogContext.tr('Summary'), value: _activitySummary(event, dialogContext)),
          if (event.findingCount != null) _ActivityDetailLine(label: dialogContext.tr('Indicators'), value: '${event.findingCount}'),
          if (event.sourceResultKey != null) _ActivityDetailLine(label: dialogContext.tr('Source report ID'), value: event.sourceResultKey!),
          if (event.parentEventId != null) _ActivityDetailLine(label: dialogContext.tr('Parent activity ID'), value: event.parentEventId!),
          if (event.runtimeExecutionId != null) _ActivityDetailLine(label: dialogContext.tr('Runtime Execution ID'), value: event.runtimeExecutionId!),
          const SizedBox(height: 8),
          Text(
            event.kind == ActivityKind.aiRequest
                ? dialogContext.tr('Prompt text is intentionally not stored. Related tool activities reference this AI request ID; execution reports and findings remain linked through their normal records.')
                : sourceResult == null
                    ? dialogContext.tr('Activity data stores only the host and bounded status metadata. The full source report was not saved or is no longer available.')
                    : dialogContext.tr('Open the source report to review full evidence.'),
            style: TextStyle(color: Colors.white.withValues(alpha: .68), height: 1.4, fontSize: 12),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Tutup'))),
          if (sourceResult != null)
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.article_outlined),
              label: Text(dialogContext.tr('Open source report')),
            ),
        ],
      ),
    );
    if (openSource == true && sourceResult != null && mounted) {
      _showResultDetails(context, sourceResult, onSaveResult: _saveResultLocally);
    }
  }

  void _clearResults() => setState(_recentResults.clear);

  void _acceptActivity(ActivityEvent event) {
    final eventsById = {for (final item in _activityEvents) item.eventId: item};
    eventsById[event.eventId] = event;
    final events = eventsById.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (mounted) setState(() => _activityEvents = events.take(500).toList(growable: false));
    _notifySecurityOverview();
  }

  void _acceptFindings(List<FindingRecord> findings) {
    final byId = {for (final finding in _findings) finding.findingId: finding};
    for (final finding in findings) {
      byId[finding.findingId] = finding;
    }
    final ordered = byId.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    if (mounted) {
      setState(() {
        _findings = ordered.take(500).toList(growable: false);
        _findingsLoaded = true;
      });
      _notifySecurityOverview();
    }
  }

  Future<void> _loadFindings() async {
    if (mounted) {
      setState(() {
        _findingsBusy = true;
        _findingsError = null;
      });
      _notifySecurityOverview();
    }
    try {
      final loaded = await _findingRepository.loadFindings(limit: 500);
      if (!mounted) return;
      final byId = {for (final finding in loaded) finding.findingId: finding};
      for (final finding in _findings) {
        byId[finding.findingId] = finding;
      }
      final ordered = byId.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      setState(() {
        _findings = ordered.take(500).toList(growable: false);
        _findingsLoaded = true;
      });
      _notifySecurityOverview();
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      if (mounted) {
        setState(() => _findingsError = 'Could not load local security findings.');
        _notifySecurityOverview();
      }
    } finally {
      if (mounted) {
        setState(() => _findingsBusy = false);
        _notifySecurityOverview();
      }
    }
  }

  Future<void> _updateFindingStatus(String findingId, FindingStatus status) async {
    try {
      final updated = await _findingRepository.updateFindingStatus(findingId, status);
      _acceptFindings([updated]);
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      if (mounted) {
        setState(() => _findingsError = 'Could not update finding status.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Could not update finding status.'))));
      }
    }
  }

  Future<void> _openFindingActivity(String assessmentId) async {
    if (_selectedIndex != 2 && mounted) setState(() => _selectedIndex = 2);
    ActivityEvent? assessmentEvent;
    for (final event in _activityEvents) {
      if (event.eventId == assessmentId) {
        assessmentEvent = event;
        break;
      }
    }
    if (assessmentEvent == null) {
      try {
        assessmentEvent = await _activityStore.loadActivityById(assessmentId);
        if (assessmentEvent != null && mounted) {
          final loadedAssessmentEvent = assessmentEvent;
          final byId = {for (final event in _activityEvents) event.eventId: event, loadedAssessmentEvent.eventId: loadedAssessmentEvent};
          setState(() => _activityEvents = byId.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)));
          _notifySecurityOverview();
        }
      } catch (error, stack) {
        DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      }
    }
    if (assessmentEvent != null && mounted) await _openActivitySource(assessmentEvent);
  }

  Future<void> _openFindingReport(String sourceReportKey) async {
    ToolRunResult? result;
    for (final candidate in [..._recentResults, ..._savedResults]) {
      if (activityResultKey(candidate.toolId, candidate.target, candidate.completedAt) == sourceReportKey) {
        result = candidate;
        break;
      }
    }
    if (result == null) {
      try {
        result = await _resultStore.loadReportById(sourceReportKey);
      } catch (error, stack) {
        DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      }
    }
    if (result != null && mounted) {
      _showResultDetails(context, result, onSaveResult: _saveResultLocally);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Source report is not available on this device.'))));
    }
  }

  Future<void> _loadActivityEvents() async {
    if (mounted) {
      setState(() {
        _activityBusy = true;
        _activityError = null;
      });
      _notifySecurityOverview();
    }
    try {
      final loaded = await _activityStore.loadActivities(limit: 500);
      if (!mounted) return;
      final eventsById = {for (final event in loaded) event.eventId: event};
      for (final event in _activityEvents) {
        eventsById[event.eventId] = event;
      }
      final events = eventsById.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      setState(() {
        _activityEvents = events.take(500).toList(growable: false);
        _activityHistoryLoaded = true;
      });
      _notifySecurityOverview();
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      if (mounted) {
        setState(() => _activityError = 'Could not load local activity history.');
        _notifySecurityOverview();
      }
    } finally {
      if (mounted) {
        setState(() => _activityBusy = false);
        _notifySecurityOverview();
      }
    }
  }

  Future<void> _clearActivityEvents() async {
    if (mounted) {
      setState(() {
        _activityBusy = true;
        _activityError = null;
      });
      _notifySecurityOverview();
    }
    try {
      await _activityStore.clearActivities();
      if (mounted) {
        setState(() {
          _activityEvents = [];
          _activityHistoryLoaded = true;
        });
        _notifySecurityOverview();
      }
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      if (mounted) {
        setState(() => _activityError = 'Could not clear local activity history.');
        _notifySecurityOverview();
      }
    } finally {
      if (mounted) {
        setState(() => _activityBusy = false);
        _notifySecurityOverview();
      }
    }
  }

  Future<void> _synchronizeMarketRuntimeAvailability() async {
    try {
      final runtimeManager = await ToolOrchestrator.sharedRuntimeManager;
      await runtimeManager.discover();
      _marketPackageManager.updateAvailableRuntimes(runtimeManager.availableRuntimeIds);
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
    }
  }

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
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
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
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
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
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      if (mounted) setState(() => _storageError = 'Could not clear local history.');
    } finally {
      if (mounted) setState(() => _storageBusy = false);
    }
  }

  Future<void> _shutdownOwnedServices() async {
    try {
      await _assessmentExecutionManager.shutdown();
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
    } finally {
      try {
        await _resultStore.close();
      } catch (error, stack) {
        DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
      } finally {
        _marketPackageManager.dispose();
        if (_ownsMarketProviderManager) _marketProviderManager.dispose();
        if (_ownsAiProviderManager) _aiProviderManager.close();
      }
    }
  }

  @override
  void dispose() {
    _assessmentExecutionManager.removeListener(_assessmentExecutionChanged);
    _terminalSession.dispose();
    _securityOverviewChanges.dispose();
    unawaited(_shutdownOwnedServices());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
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
        findings: List.unmodifiable(_findings),
        findingsLoaded: _findingsLoaded,
        findingsBusy: _findingsBusy,
        findingsError: _findingsError,
        activityEvents: List.unmodifiable(_activityEvents),
        activityLoaded: _activityHistoryLoaded,
        activityBusy: _activityBusy,
        activityError: _activityError,
        marketPackageManager: _marketPackageManager,
        assessmentProgress: _assessmentExecutionManager.progress,
        activeAssessmentTarget: _assessmentExecutionManager.activeRun == null
            ? null
            : sanitizeActivityTarget(_assessmentExecutionManager.activeRun!.target),
        onNavigateToTools: () => _selectDestination(1),
        onOpenCatalog: _openCatalog,
        onNavigateToReports: () => _selectDestination(2),
        onNavigateToFindings: _navigateToFindings,
        onOpenSecurityOverview: _openSecurityOverview,
        onOpenAssistant: _openAssistantModule,
        onOpenActivity: (event) => unawaited(_openActivitySource(event)),
        onOpenResult: (result) => _showResultDetails(context, result, onSaveResult: _saveResultLocally),
        onSaveResult: _saveResultLocally,
      ),
      ToolsScreen(
        packageManager: _marketPackageManager,
        assessmentExecutionManager: _assessmentExecutionManager,
      ),
      ReportsScreen(
        openFindingsOnOpen: _openFindingsOnReports,
        initialFindingSeverity: _openFindingsSeverity,
        recentResults: recentResults,
        savedResults: savedResults,
        savedHistoryLoaded: _savedHistoryLoaded,
        storageBusy: _storageBusy,
        storageError: _storageError,
        onLoadSavedResults: _loadSavedResults,
        onClearResults: _clearResults,
        onClearSavedResults: _clearSavedResults,
        onSaveResult: _saveResultLocally,
        activityEvents: List.unmodifiable(_activityEvents),
        activityHistoryLoaded: _activityHistoryLoaded,
        activityBusy: _activityBusy,
        activityError: _activityError,
        onLoadActivities: _loadActivityEvents,
        onClearActivities: _clearActivityEvents,
        onOpenActivitySource: _openActivitySource,
        findings: List.unmodifiable(_findings),
        findingsLoaded: _findingsLoaded,
        findingsBusy: _findingsBusy,
        findingsError: _findingsError,
        onLoadFindings: _loadFindings,
        onUpdateFindingStatus: _updateFindingStatus,
        onOpenFindingReport: _openFindingReport,
        onOpenFindingActivity: _openFindingActivity,
      ),
      SettingsScreen(
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
        onOpenAssistant: _openAssistantModule,
        onOpenConnections: (category) => _openConnections(initialCategory: category),
        onOpenAssessment: () => _selectDestination(1),
        onOpenReports: () => _selectDestination(2),
        onOpenDiagnostics: _openDiagnostics,
      ),
    ];
    final page = AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 230),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => reduceMotion
          ? child
          : FadeTransition(
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
        actions: [
          IconButton(
            tooltip: context.tr('Open Edge Panel'),
            onPressed: () => setState(() => _edgePanelOpen = true),
            icon: const Icon(Icons.bolt_rounded, color: _mint),
          ),
          const Center(child: _ModeBadge()),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final terminalWidth = math.min(400.0, math.max(0.0, constraints.maxWidth - 16)).toDouble();
          final terminalHeight = math.min(480.0, math.max(0.0, constraints.maxHeight - 16)).toDouble();
          final visibleTerminalHeight = _terminalMinimized ? 56.0 : terminalHeight;
          final requestedPosition = _terminalPosition ?? Offset(
            math.max(8.0, constraints.maxWidth - terminalWidth - 12).toDouble(),
            math.max(8.0, constraints.maxHeight - terminalHeight - 12).toDouble(),
          );
          final terminalPosition = Offset(
            requestedPosition.dx.clamp(0.0, math.max(0.0, constraints.maxWidth - terminalWidth)).toDouble(),
            requestedPosition.dy.clamp(0.0, math.max(0.0, constraints.maxHeight - visibleTerminalHeight)).toDouble(),
          );
          return Stack(clipBehavior: Clip.hardEdge, children: [
            Row(children: [
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
            if (_edgePanelOpen)
              Positioned.fill(
                child: Stack(children: [
                  GestureDetector(
                    onTap: () => setState(() => _edgePanelOpen = false),
                    child: ColoredBox(color: Colors.black.withValues(alpha: .52)),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: EdgePanel(
                      cloudflareConnected: _marketProviderManager.statusFor('cloudflare') == ManagedProviderStatus.connected,
                      geminiConnected: _marketProviderManager.statusFor('gemini') == ManagedProviderStatus.connected,
                      onOpenCloudflareDashboard: () {
                        setState(() => _edgePanelOpen = false);
                        _openCloudflareDashboard();
                      },
                      onOpenGeminiDetails: () {
                        setState(() => _edgePanelOpen = false);
                        _openGeminiProviderDetails();
                      },
                      onClose: () => setState(() => _edgePanelOpen = false),
                      onOpenTerminal: _openTerminalWorkspace,
                      onOpenAssessment: () {
                        setState(() => _edgePanelOpen = false);
                        _selectDestination(1);
                      },
                      onOpenCatalog: () {
                        setState(() => _edgePanelOpen = false);
                        _openCatalog();
                      },
                      onOpenReports: () {
                        setState(() => _edgePanelOpen = false);
                        _selectDestination(2);
                      },
                      onOpenSettings: () {
                        setState(() => _edgePanelOpen = false);
                        _selectDestination(3);
                      },
                      onOpenConnections: () {
                        setState(() => _edgePanelOpen = false);
                        _openConnections();
                      },
                    ),
                  ),
                ]),
              ),
            if (_terminalOpen)
              Positioned(
                left: terminalPosition.dx,
                top: terminalPosition.dy,
                width: terminalWidth,
                height: visibleTerminalHeight,
                child: AnimatedBuilder(
                  animation: _terminalSession,
                  builder: (context, _) => _terminalMinimized
                      ? MinimizedTerminal(
                          status: _terminalSession.status,
                          onExpand: () => setState(() => _terminalMinimized = false),
                          onExit: _exitMinimizedTerminal,
                          canExit: _terminalSession.status != TerminalSessionStatus.running,
                        )
                      : FloatingTerminal(
                          key: const ValueKey('floating-terminal-workspace'),
                          session: _terminalSession,
                          executor: _terminalExecutor,
                          onMinimize: () => setState(() => _terminalMinimized = true),
                          onExit: _closeTerminalWorkspace,
                          onDrag: (delta) => _moveTerminal(delta, constraints.biggest, Size(terminalWidth, terminalHeight)),
                        ),
                ),
              ),
          ]);
        }),
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

class _ReportEntry {
  const _ReportEntry({required this.result, required this.saved});
  final ToolRunResult result;
  final bool saved;
}

enum _ReportFilter { all, session, saved }
enum _ReportContent { reports, findings, activity }
enum _ActivityDateFilter { all, today, week, month }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    this.openFindingsOnOpen = false,
    this.initialFindingSeverity,
    required this.recentResults,
    required this.savedResults,
    required this.savedHistoryLoaded,
    required this.storageBusy,
    required this.storageError,
    required this.onLoadSavedResults,
    required this.onClearResults,
    required this.onClearSavedResults,
    required this.onSaveResult,
    this.activityEvents = const [],
    this.activityHistoryLoaded = false,
    this.activityBusy = false,
    this.activityError,
    this.onLoadActivities,
    this.onClearActivities,
    this.onOpenActivitySource,
    this.findings = const [],
    this.findingsLoaded = false,
    this.findingsBusy = false,
    this.findingsError,
    this.onLoadFindings,
    this.onUpdateFindingStatus,
    this.onOpenFindingReport,
    this.onOpenFindingActivity,
  });

  final bool openFindingsOnOpen;
  final FindingSeverity? initialFindingSeverity;
  final List<ToolRunResult> recentResults;
  final List<ToolRunResult> savedResults;
  final bool savedHistoryLoaded;
  final bool storageBusy;
  final String? storageError;
  final Future<void> Function() onLoadSavedResults;
  final VoidCallback onClearResults;
  final Future<void> Function() onClearSavedResults;
  final Future<bool> Function(ToolRunResult) onSaveResult;
  final List<ActivityEvent> activityEvents;
  final bool activityHistoryLoaded;
  final bool activityBusy;
  final String? activityError;
  final Future<void> Function()? onLoadActivities;
  final Future<void> Function()? onClearActivities;
  final ValueChanged<ActivityEvent>? onOpenActivitySource;
  final List<FindingRecord> findings;
  final bool findingsLoaded;
  final bool findingsBusy;
  final String? findingsError;
  final Future<void> Function()? onLoadFindings;
  final Future<void> Function(String findingId, FindingStatus status)? onUpdateFindingStatus;
  final Future<void> Function(String sourceReportKey)? onOpenFindingReport;
  final Future<void> Function(String assessmentId)? onOpenFindingActivity;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportFilter _filter = _ReportFilter.all;
  _ReportContent _content = _ReportContent.reports;
  final _activityTargetController = TextEditingController();
  final _findingQueryController = TextEditingController();
  final _findingTargetController = TextEditingController();
  final _findingCategoryController = TextEditingController();
  FindingSeverity? _findingSeverity;
  FindingStatus? _findingStatus;
  _ActivityDateFilter _activityDateFilter = _ActivityDateFilter.all;
  ActivityKind? _activityKind;
  String? _activityToolId;
  ActivityStatus? _activityStatus;
  int _activityVisibleCount = 30;
  int _findingVisibleCount = 30;
  int _reportVisibleCount = 30;

  @override
  void initState() {
    super.initState();
    if (widget.openFindingsOnOpen) _content = _ReportContent.findings;
    _findingSeverity = widget.initialFindingSeverity;
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openFindingsOnOpen != widget.openFindingsOnOpen) {
      _content = widget.openFindingsOnOpen ? _ReportContent.findings : _ReportContent.reports;
    }
    if (oldWidget.initialFindingSeverity != widget.initialFindingSeverity) {
      _findingSeverity = widget.initialFindingSeverity;
    }
  }

  @override
  void dispose() {
    _activityTargetController.dispose();
    _findingQueryController.dispose();
    _findingTargetController.dispose();
    _findingCategoryController.dispose();
    super.dispose();
  }

  Future<void> _openFindingDetails(FindingRecord finding) async {
    final sourceAction = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Finding details')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                _FindingTag(label: _severityName(finding.severity, dialogContext), color: _findingColor(finding.severity)),
                _FindingTag(label: dialogContext.tr(finding.confidence.name), color: const Color(0xFF98A7BD)),
                _FindingTag(label: _findingStatusLabel(finding.status, dialogContext), color: _findingStatusColor(finding.status)),
              ]),
              const SizedBox(height: 12),
              _ActivityDetailLine(label: dialogContext.tr('Category'), value: finding.category),
              _ActivityDetailLine(label: dialogContext.tr('Target'), value: finding.target),
              _ActivityDetailLine(label: dialogContext.tr('Description'), value: finding.description),
              _ActivityDetailLine(label: dialogContext.tr('Recommendation'), value: finding.recommendation),
              _ActivityDetailLine(label: dialogContext.tr('First seen'), value: finding.firstSeen.toLocal().toString()),
              _ActivityDetailLine(label: dialogContext.tr('Last seen'), value: finding.lastSeen.toLocal().toString()),
              if (finding.sourceTool != null) _ActivityDetailLine(label: dialogContext.tr('Source tool'), value: finding.sourceTool!),
              if (finding.assessmentId != null) _ActivityDetailLine(label: dialogContext.tr('Assessment ID'), value: finding.assessmentId!),
              if (finding.evidence.isNotEmpty) ...[
                Text(dialogContext.tr('Evidence'), style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final item in finding.evidence) Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText('• $item')),
              ],
              if (finding.sourceReportKeys.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(dialogContext.tr('Source reports'), style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final key in finding.sourceReportKeys)
                  TextButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(key),
                    icon: const Icon(Icons.article_outlined),
                    label: Text(dialogContext.tr('Open source report')),
                  ),
              ],
            ]),
          ),
        ),
        actions: [
          if (finding.assessmentId != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('activity:${finding.assessmentId}'),
              child: Text(dialogContext.tr('Open assessment activity')),
            ),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(dialogContext.tr('Tutup'))),
        ],
      ),
    );
    if (!mounted || sourceAction == null) return;
    if (sourceAction.startsWith('activity:')) {
      setState(() => _content = _ReportContent.activity);
      await widget.onOpenFindingActivity?.call(sourceAction.substring('activity:'.length));
    } else {
      await widget.onOpenFindingReport?.call(sourceAction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rowsByReportId = <String, _ReportEntry>{};
    if (_filter != _ReportFilter.saved) {
      for (final result in widget.recentResults) {
        rowsByReportId[activityResultKey(result.toolId, result.target, result.completedAt)] = _ReportEntry(result: result, saved: false);
      }
    }
    if (_filter != _ReportFilter.session) {
      for (final result in widget.savedResults) {
        rowsByReportId[activityResultKey(result.toolId, result.target, result.completedAt)] = _ReportEntry(result: result, saved: true);
      }
    }
    final rows = rowsByReportId.values.toList()
      ..sort((a, b) => b.result.completedAt.compareTo(a.result.completedAt));
    final findingQuery = _findingQueryController.text.trim().toLowerCase();
    final findingTarget = _findingTargetController.text.trim().toLowerCase();
    final findingCategory = _findingCategoryController.text.trim().toLowerCase();
    final findings = widget.findings.where((finding) {
      if (_findingSeverity != null && finding.severity != _findingSeverity) return false;
      if (_findingStatus != null && finding.status != _findingStatus) return false;
      if (findingCategory.isNotEmpty && !finding.category.toLowerCase().contains(findingCategory)) return false;
      if (findingTarget.isNotEmpty && !finding.target.toLowerCase().contains(findingTarget)) return false;
      if (findingQuery.isNotEmpty) {
        final searchable = '${finding.title} ${finding.category} ${finding.target} ${finding.description} ${finding.recommendation} ${finding.evidence.join(' ')}'.toLowerCase();
        if (!searchable.contains(findingQuery)) return false;
      }
      return true;
    }).toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    final now = DateTime.now();
    final activityFrom = switch (_activityDateFilter) {
      _ActivityDateFilter.all => null,
      _ActivityDateFilter.today => DateTime(now.year, now.month, now.day).toUtc(),
      _ActivityDateFilter.week => now.subtract(const Duration(days: 7)).toUtc(),
      _ActivityDateFilter.month => now.subtract(const Duration(days: 30)).toUtc(),
    };
    final targetQuery = _activityTargetController.text.trim().toLowerCase();
    final activities = widget.activityEvents.where((event) {
      if (activityFrom != null && event.startedAt.isBefore(activityFrom)) return false;
      if (_activityKind != null && event.kind != _activityKind) return false;
      if (_activityToolId != null && event.toolId != _activityToolId) return false;
      if (_activityStatus != null && event.status != _activityStatus) return false;
      if (targetQuery.isNotEmpty && !event.target.toLowerCase().contains(targetQuery)) return false;
      return true;
    }).toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final visibleRows = rows.take(_reportVisibleCount).toList(growable: false);
    final visibleFindings = findings.take(_findingVisibleCount).toList(growable: false);
    final visibleActivities = activities.take(_activityVisibleCount).toList(growable: false);
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
          SegmentedButton<_ReportContent>(
            segments: [
              ButtonSegment(
                value: _ReportContent.reports,
                icon: const Icon(Icons.article_outlined),
                label: Text(context.tr('Reports')),
              ),
              ButtonSegment(
                value: _ReportContent.findings,
                icon: const Icon(Icons.rule_folder_outlined),
                label: Text(context.tr('Findings')),
              ),
              ButtonSegment(
                value: _ReportContent.activity,
                icon: const Icon(Icons.timeline_rounded),
                label: Text(context.tr('Activity')),
              ),
            ],
            selected: {_content},
            onSelectionChanged: (selection) => setState(() => _content = selection.first),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(switch (_content) {
              _ReportContent.reports => 'Reports show complete check results and evidence.',
              _ReportContent.findings => 'Findings are indicators from checks, not proof that a system is vulnerable.',
              _ReportContent.activity => 'Activity records what the assessment engine actually attempted and completed.',
            }),
            style: TextStyle(color: Colors.white.withValues(alpha: .68), height: 1.4, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_content != _ReportContent.activity)
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
          if (_content == _ReportContent.reports && _filter != _ReportFilter.saved && widget.recentResults.isNotEmpty)
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
          if (_content != _ReportContent.activity && _filter != _ReportFilter.session)
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
          if (_content != _ReportContent.activity && widget.storageError != null) ...[
            const SizedBox(height: 8),
            Text(_translateStorageError(context, widget.storageError!), style: const TextStyle(color: Colors.orangeAccent)),
          ],
          const SizedBox(height: 8),
          if (_content == _ReportContent.activity) ...[
            TextField(
              controller: _activityTargetController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: context.tr('Filter activity by target'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final filter in _ActivityDateFilter.values)
                ChoiceChip(
                  label: Text(context.tr(switch (filter) {
                    _ActivityDateFilter.all => 'All time',
                    _ActivityDateFilter.today => 'Today',
                    _ActivityDateFilter.week => 'Last 7 days',
                    _ActivityDateFilter.month => 'Last 30 days',
                  })),
                  selected: _activityDateFilter == filter,
                  onSelected: (_) => setState(() => _activityDateFilter = filter),
                ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ChoiceChip(
                label: Text(context.tr('All activity types')),
                selected: _activityKind == null && _activityToolId == null,
                onSelected: (_) => setState(() {
                  _activityKind = null;
                  _activityToolId = null;
                }),
              ),
              ChoiceChip(
                label: Text(context.tr('Assessments')),
                selected: _activityKind == ActivityKind.assessment,
                onSelected: (_) => setState(() {
                  _activityKind = ActivityKind.assessment;
                  _activityToolId = null;
                }),
              ),
              ChoiceChip(
                label: Text(context.tr('All tools')),
                selected: _activityKind == ActivityKind.tool && _activityToolId == null,
                onSelected: (_) => setState(() {
                  _activityKind = ActivityKind.tool;
                  _activityToolId = null;
                }),
              ),
              ChoiceChip(
                label: Text(context.tr('AI requests')),
                selected: _activityKind == ActivityKind.aiRequest,
                onSelected: (_) => setState(() {
                  _activityKind = ActivityKind.aiRequest;
                  _activityToolId = null;
                }),
              ),
              for (final toolId in const ['dns_lookup', 'tls_inspector', 'http_headers', 'response_analyzer'])
                ChoiceChip(
                  label: Text(_toolDisplayName(toolId, context)),
                  selected: _activityToolId == toolId,
                  onSelected: (_) => setState(() {
                    _activityKind = ActivityKind.tool;
                    _activityToolId = toolId;
                  }),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(labelText: context.tr('Activity status'), isDense: true),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ActivityStatus?>(
                      key: const ValueKey('activity-status-filter'),
                      value: _activityStatus,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(value: null, child: Text(context.tr('Any status'))),
                        for (final status in ActivityStatus.values)
                          DropdownMenuItem(value: status, child: Text(_activityStatusLabel(status, context))),
                      ],
                      onChanged: (status) => setState(() => _activityStatus = status),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('Refresh activity'),
                onPressed: widget.activityBusy ? null : () => widget.onLoadActivities?.call(),
                icon: widget.activityBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
              if (widget.activityEvents.isNotEmpty)
                IconButton(
                  tooltip: context.tr('Clear activity'),
                  onPressed: widget.activityBusy ? null : () => _confirmClearActivity(context, widget.onClearActivities),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ]),
            if (widget.activityError != null) ...[
              const SizedBox(height: 8),
              Text(context.tr(widget.activityError!), style: const TextStyle(color: Colors.orangeAccent)),
            ],
            const SizedBox(height: 8),
            if ((widget.activityBusy || !widget.activityHistoryLoaded) && widget.activityEvents.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (activities.isEmpty)
              _EmptyState(
                icon: Icons.timeline_rounded,
                title: context.tr('No activity matches these filters'),
                detail: context.tr('Run a security assessment or an individual tool. Only attempted and completed work is recorded.'),
              )
            else ...[
              for (final event in visibleActivities) ...[
                _ActivityCard(
                  key: ValueKey('activity-${event.eventId}'),
                  event: event,
                  onTap: () => widget.onOpenActivitySource?.call(event),
                ),
                const SizedBox(height: 8),
              ],
              if (activities.length > visibleActivities.length)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _activityVisibleCount += 30),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text('${context.tr('Load more')} (${visibleActivities.length}/${activities.length})'),
                  ),
                ),
            ],
          ] else if (_content == _ReportContent.findings) ...[
            TextField(
              key: const ValueKey('finding-search-filter'),
              controller: _findingQueryController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: context.tr('Search findings'), isDense: true),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('finding-target-filter'),
                  controller: _findingTargetController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: context.tr('Target'), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('finding-category-filter'),
                  controller: _findingCategoryController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: context.tr('Category'), isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(labelText: context.tr('Severity'), isDense: true),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<FindingSeverity?>(
                      key: const ValueKey('finding-severity-filter'),
                      value: _findingSeverity,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(value: null, child: Text(context.tr('All severities'))),
                        for (final severity in FindingSeverity.values)
                          DropdownMenuItem(value: severity, child: Text(_severityName(severity, context))),
                      ],
                      onChanged: (value) => setState(() => _findingSeverity = value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(labelText: context.tr('Finding status'), isDense: true),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<FindingStatus?>(
                      key: const ValueKey('finding-status-filter'),
                      value: _findingStatus,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(value: null, child: Text(context.tr('All statuses'))),
                        for (final status in FindingStatus.values)
                          DropdownMenuItem(value: status, child: Text(_findingStatusLabel(status, context))),
                      ],
                      onChanged: (value) => setState(() => _findingStatus = value),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('Refresh findings'),
                onPressed: widget.findingsBusy ? null : () => widget.onLoadFindings?.call(),
                icon: widget.findingsBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
              ),
            ]),
            const SizedBox(height: 8),
            Text(context.tr('Findings are independent, reviewable indicators; an Error is not a vulnerability, and no indicator does not prove a target is secure.'),
                style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 12, height: 1.4)),
            if (widget.findingsError != null) ...[
              const SizedBox(height: 8),
              Text(context.tr(widget.findingsError!), style: const TextStyle(color: Colors.orangeAccent)),
            ],
            const SizedBox(height: 8),
            if (widget.findingsBusy && !widget.findingsLoaded)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (findings.isEmpty)
              _EmptyState(
                icon: Icons.rule_folder_outlined,
                title: context.tr('No findings match these filters'),
                detail: context.tr('Run a check that produces an indicator, or revise the filters. Finding status is managed separately from report history.'),
              )
            else ...[
              for (final finding in visibleFindings) ...[
                _StoredFindingCard(
                  key: ValueKey('finding-${finding.findingId}'),
                  finding: finding,
                  onTap: () => _openFindingDetails(finding),
                  onStatusChanged: (status) => widget.onUpdateFindingStatus?.call(finding.findingId, status),
                ),
                const SizedBox(height: 8),
              ],
              if (findings.length > visibleFindings.length)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _findingVisibleCount += 30),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text('${context.tr('Load more')} (${visibleFindings.length}/${findings.length})'),
                  ),
                ),
            ],
          ] else if (widget.storageBusy && rows.isEmpty && _filter != _ReportFilter.session)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            _EmptyState(
              icon: Icons.article_outlined,
              title: context.tr('No reports in this view'),
              detail: context.tr('Run a local check, or save a result from its details to keep it after closing the app.'),
            )
          else ...[
            for (final entry in visibleRows) ...[
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
            if (rows.length > visibleRows.length)
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _reportVisibleCount += 30),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text('${context.tr('Load more')} (${visibleRows.length}/${rows.length})'),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(context.tr('Only assess systems you own or have permission to test. App confirmation is not legal proof of authorization.'),
              style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 12, height: 1.45)),
        ]),
      ),
    );
  }
}

class _ActivityDetailLine extends StatelessWidget {
  const _ActivityDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .58), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(height: 1.35)),
        ]),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({super.key, required this.event, required this.onTap});

  final ActivityEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _activityStatusColor(event.status);
    final title = event.kind == ActivityKind.assessment
        ? context.tr('Assessment run')
        : event.kind == ActivityKind.aiRequest
            ? context.tr('AI request')
            : _toolDisplayName(event.toolId ?? '', context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
              child: Icon(event.kind == ActivityKind.assessment
                  ? Icons.radar_rounded
                  : event.kind == ActivityKind.aiRequest
                      ? Icons.auto_awesome_outlined
                      : _toolIcon(event.toolId ?? ''), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(width: 6),
                _FindingTag(label: _activityStatusLabel(event.status, context), color: color),
              ]),
              const SizedBox(height: 4),
              Text('${event.target} · ${event.startedAt.toLocal()}',
                  style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 11, height: 1.35)),
              if (event.finishedAt != null)
                Text('${context.tr('Finished')}: ${event.finishedAt!.toLocal()}',
                    style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11)),
              if (event.summary != null) ...[
                const SizedBox(height: 6),
                Text(_activitySummary(event, context), style: TextStyle(color: Colors.white.withValues(alpha: .8), height: 1.35)),
              ],
              if (event.findingCount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('${context.tr('Indicators')}: ${event.findingCount}',
                      style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 11)),
                ),
              if (event.parentEventId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(context.tr('Part of an assessment run'),
                      style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11)),
                ),
            ])),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

class _StoredFindingCard extends StatelessWidget {
  const _StoredFindingCard({super.key, required this.finding, required this.onTap, required this.onStatusChanged});

  final FindingRecord finding;
  final VoidCallback onTap;
  final ValueChanged<FindingStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    _FindingTag(label: _severityName(finding.severity, context), color: _findingColor(finding.severity)),
                    _FindingTag(label: context.tr(finding.confidence.name), color: const Color(0xFF98A7BD)),
                    _FindingTag(label: _findingStatusLabel(finding.status, context), color: _findingStatusColor(finding.status)),
                  ]),
                ),
                PopupMenuButton<FindingStatus>(
                  key: ValueKey('finding-status-${finding.findingId}'),
                  tooltip: context.tr('Change finding status'),
                  onSelected: onStatusChanged,
                  itemBuilder: (context) => [
                    for (final status in FindingStatus.values)
                      PopupMenuItem(value: status, child: Text(_findingStatusLabel(status, context))),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ]),
              const SizedBox(height: 8),
              Text(finding.title, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
              const SizedBox(height: 5),
              Text('${finding.category} · ${finding.target}', style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12)),
              const SizedBox(height: 6),
              Text(finding.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.35)),
              const SizedBox(height: 6),
              Text('${context.tr('First seen')}: ${finding.firstSeen.toLocal()} · ${context.tr('Last seen')}: ${finding.lastSeen.toLocal()}',
                  style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11)),
              if (finding.sourceReportKeys.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('${context.tr('Source reports:')} ${finding.sourceReportKeys.length}',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ),
      );
}

Color _findingStatusColor(FindingStatus status) => switch (status) {
      FindingStatus.open => const Color(0xFF71B7FF),
      FindingStatus.inProgress => Colors.orangeAccent,
      FindingStatus.resolved => _mint,
      FindingStatus.accepted => const Color(0xFFAA9AFF),
      FindingStatus.falsePositive => Colors.white54,
    };

String _findingStatusLabel(FindingStatus status, BuildContext context) => switch (status) {
      FindingStatus.open => context.tr('Open'),
      FindingStatus.inProgress => context.tr('In Progress'),
      FindingStatus.resolved => context.tr('Resolved'),
      FindingStatus.accepted => context.tr('Accepted'),
      FindingStatus.falsePositive => context.tr('False Positive'),
    };

Color _activityStatusColor(ActivityStatus status) => switch (status) {
      ActivityStatus.started || ActivityStatus.running => const Color(0xFF71B7FF),
      ActivityStatus.completed => _mint,
      ActivityStatus.failed => Colors.orangeAccent,
      ActivityStatus.cancelled => Colors.white54,
    };

String _activityStatusLabel(ActivityStatus status, BuildContext context) => switch (status) {
      ActivityStatus.started => context.tr('Started'),
      ActivityStatus.running => context.tr('Running'),
      ActivityStatus.completed => context.tr('Completed'),
      ActivityStatus.failed => context.tr('Failed'),
      ActivityStatus.cancelled => context.tr('Cancelled'),
    };

String _activitySummary(ActivityEvent event, BuildContext context) {
  final summary = event.summary ?? '';
  if (summary == 'Check cancelled.') return context.tr(summary);
  if (event.kind == ActivityKind.assessment || event.kind == ActivityKind.aiRequest || event.toolId == 'terminal_workspace') return activitySummaryText(event, context);
  if (event.kind == ActivityKind.tool) return _displayResultSummary(summary, context);
  return summary;
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

class _FindingTag extends StatelessWidget {
  const _FindingTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(24)),
        child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

Color _findingColor(FindingSeverity severity) => switch (severity) {
      FindingSeverity.critical => const Color(0xFFFF3B5C),
      FindingSeverity.high => const Color(0xFFFF7070),
      FindingSeverity.medium => Colors.orangeAccent,
      FindingSeverity.low => const Color(0xFF71B7FF),
      FindingSeverity.info => _mint,
    };

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required this.onOpenAssistant,
    required this.onOpenConnections,
    required this.onOpenAssessment,
    required this.onOpenReports,
    required this.onOpenDiagnostics,
  });

  final Locale locale;
  final ValueChanged<Locale>? onLocaleChanged;
  final VoidCallback onOpenAssistant;
  final ValueChanged<ProviderCategory?> onOpenConnections;
  final VoidCallback onOpenAssessment;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenDiagnostics;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), children: [
            Text(context.tr('SETTINGS'), style: _eyebrow(context)),
            const SizedBox(height: 8),
            Text(context.tr('Preferences and privacy'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            _SettingsSectionHeader(title: context.tr('GENERAL SETTINGS'), icon: Icons.tune_rounded),
            const SizedBox(height: 8),
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
            const SizedBox(height: 16),
            _SettingsSectionHeader(title: context.tr('SECURITY & PRIVACY'), icon: Icons.shield_outlined),
            const SizedBox(height: 8),
            _SettingsInfoCard(
              icon: Icons.lock_outline_rounded,
              title: context.tr('Security & privacy'),
              body: context.tr('Checks stay on-device by default. Each network assessment asks for target-specific authorization; this app does not verify legal permission.'),
            ),
            const SizedBox(height: 16),
            _SettingsSectionHeader(title: context.tr('AI PROVIDERS'), icon: Icons.auto_awesome_outlined),
            const SizedBox(height: 8),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.hub_outlined, color: _mint),
                  title: Text(context.tr('AI provider catalog')),
                  subtitle: Text(context.tr('Configure a supported provider and use per-request privacy consent for AI analysis.')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onOpenConnections(ProviderCategory.ai),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFAA9AFF)),
                  title: Text(context.tr('AI Assistant')),
                  subtitle: Text(context.tr('Gemini can be used after setup; unconfigured providers remain inactive.')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenAssistant,
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _SettingsSectionHeader(title: context.tr('CLOUD PROVIDERS'), icon: Icons.cloud_outlined),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.hub_outlined, color: _mint),
                title: Text(context.tr('Connections and providers')),
                subtitle: Text(context.tr('Review provider guides and endpoint test limits; cloud connectors are not active.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onOpenConnections(null),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSectionHeader(title: context.tr('RUNTIME & TOOLS'), icon: Icons.build_circle_outlined),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.radar_rounded, color: _mint),
                title: Text(context.tr('Assessment and local tools')),
                subtitle: Text(context.tr('Review available checks and run an authorized assessment.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenAssessment,
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSectionHeader(title: context.tr('PERMISSIONS'), icon: Icons.key_outlined),
            const SizedBox(height: 8),
            _SettingsInfoCard(
              icon: Icons.fact_check_outlined,
              title: context.tr('Authorization is confirmed per assessment'),
              body: context.tr('There is no global permission toggle. Confirm only targets you own or are authorized to assess.'),
            ),
            const SizedBox(height: 16),
            _SettingsSectionHeader(title: context.tr('STORAGE & DATA'), icon: Icons.storage_outlined),
            const SizedBox(height: 8),
            Card(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.lock_outline_rounded, color: _mint),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.tr('Privacy and local storage'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Text(context.tr('Saved reports use app-private SQLite. Data is not encrypted or synced.'),
                          style: TextStyle(color: Colors.white.withValues(alpha: .68), height: 1.45)),
                    ])),
                  ]),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.article_outlined, color: _mint),
                  title: Text(context.tr('Manage reports and local data')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenReports,
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _SettingsSectionHeader(title: context.tr('DIAGNOSTICS'), icon: Icons.monitor_heart_outlined),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.bug_report_outlined, color: _mint),
                title: Text(context.tr('Developer Diagnostics')),
                subtitle: Text(context.tr('Local error queue, device-safe details and optional relay settings.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenDiagnostics,
              ),
            ),
          ]),
        ),
      );
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: _mint, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(color: Colors.white.withValues(alpha: .74), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .55))),
      ]);
}

class _SettingsInfoCard extends StatelessWidget {
  const _SettingsInfoCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: _mint),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(body, style: TextStyle(color: Colors.white.withValues(alpha: .68), height: 1.45, fontSize: 12)),
            ])),
          ]),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;

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
      'terminal_workspace' => context.tr('Terminal workspace'),
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
      FindingSeverity.critical => context.tr('Critical'),
      FindingSeverity.high => context.tr('High'),
      FindingSeverity.medium => context.tr('Medium'),
      FindingSeverity.low => context.tr('Low'),
      FindingSeverity.info => context.tr('Informational'),
    };

String _displayRecommendation(String recommendation, BuildContext context) => context.tr(recommendation);

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({
    super.key,
    required this.packageManager,
    required this.assessmentExecutionManager,
  });

  final MarketPackageManager packageManager;
  final AssessmentExecutionManager assessmentExecutionManager;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Text(context.tr('SECURITY ASSESSMENT'), style: _eyebrow(context)),
              const SizedBox(height: 8),
              Text(context.tr('Security Assessment'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(context.tr('Choose an authorized target, select checks, then review results and findings.'),
                  style: TextStyle(color: Colors.white.withValues(alpha: .72), height: 1.45)),
              const SizedBox(height: 14),
              AssessmentRunner(
                packageManager: packageManager,
                executionManager: assessmentExecutionManager,
              ),
            ],
          ),
        ),
      );
}

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, this.initialCategory});

  final ProviderCategory? initialCategory;

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

  @override
  void initState() {
    super.initState();
    _selectedProviderCategory = widget.initialCategory;
  }

  List<ProviderDefinition> _visibleProviders(BuildContext context) {
    final query = _providerSearchController.text.trim().toLowerCase();
    return providerRegistry.where((provider) {
      // Priority Cloudflare configuration and verification now live in Market;
      // do not expose a second generic credential-only configuration surface here.
      if (provider.id == 'cloudflare') return false;
      final matchesCategory = _selectedProviderCategory == null ||
          provider.category == _selectedProviderCategory ||
          (_selectedProviderCategory == ProviderCategory.ai && provider.category == ProviderCategory.onDeviceAi);
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
          Text(context.tr('Local checks work without cloud accounts. Gemini inference is available after you save a user-owned API key; each prompt and approved tool result requires explicit data-sharing consent.'),
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
          _ConnectionRow(name: context.tr('Penyedia AI'), detail: context.tr('Gemini needs a saved API key; Local AI stays Not Ready until a real on-device runtime and model are integrated.'), icon: Icons.auto_awesome_outlined),
          const SizedBox(height: 10),
          _ConnectionRow(name: context.tr('Penyimpanan cloud'), detail: context.tr('Belum dikonfigurasi'), icon: Icons.folder_open_outlined),
          const SizedBox(height: 22),
          _SectionTitle(title: context.tr('Katalog penyedia layanan'), icon: Icons.apps_outlined),
          const SizedBox(height: 10),
          Text(context.tr('Gemini is available through the Assistant when configured. Other catalog entries remain guides unless their specific adapter is marked available.'),
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
            for (final category in ProviderCategory.values.where((category) => category != ProviderCategory.cloudInfrastructure))
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
      'cloudflare' => (Icons.cloud_rounded, const Color(0xFFF38020), 'CF'),
      _ => switch (provider.category) {
          ProviderCategory.cloudInfrastructure => (Icons.cloud_rounded, const Color(0xFFF38020), 'CF'),
          ProviderCategory.backend => (Icons.cloud_outlined, const Color(0xFF7BA8E8), 'API'),
          ProviderCategory.database => (Icons.storage_rounded, const Color(0xFF5BC0BE), 'DB'),
          ProviderCategory.storage => (Icons.folder_open_rounded, const Color(0xFF6EB6D8), 'IO'),
          ProviderCategory.ai => (Icons.auto_awesome_rounded, const Color(0xFF9A8BFF), 'AI'),
          ProviderCategory.onDeviceAi => (Icons.phone_android_rounded, const Color(0xFF73F0C2), 'AI'),
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
      ToolStatus.ready => context.tr('Siap dijalankan'),
      ToolStatus.installed => context.tr('Terpasang'),
      ToolStatus.downloadRequired => context.tr('Memerlukan unduhan'),
      ToolStatus.runtimeRequired => context.tr('Memerlukan runtime'),
      ToolStatus.dependencyRequired => context.tr('Memerlukan dependensi'),
      ToolStatus.permissionRequired => context.tr('Memerlukan izin'),
      ToolStatus.notInstalled => context.tr('Belum terpasang'),
      ToolStatus.environmentRequired => context.tr('Memerlukan konfigurasi'),
      ToolStatus.limitedCompatibility => context.tr('Kompatibilitas terbatas'),
      ToolStatus.unsupported => context.tr('Tidak didukung'),
      ToolStatus.disabled => context.tr('Dinonaktifkan'),
      ToolStatus.error => context.tr('Kesalahan kesiapan'),
    };

String _providerCategoryName(ProviderCategory category, BuildContext context) => context.tr(providerCategoryLabel(category));

String _providerDescription(ProviderDefinition provider, BuildContext context) => switch (provider.id) {
      'local_ai' => context.tr('Runtime inferensi lokal opsional di perangkat; tidak ada fallback cloud.'),
      'openai' => context.tr('Penyedia AI opsional. Kunci dapat disimpan lokal, tetapi belum ada permintaan API.'),
      'gemini' => context.tr('Penyedia AI Google. Inferensi Gemini aktif setelah konfigurasi API key dan persetujuan pembagian data.'),
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

Future<void> _confirmClearActivity(BuildContext context, Future<void> Function()? onClear) async {
  if (onClear == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.tr('Clear local activity?')),
      content: Text(dialogContext.tr('This removes the local activity timeline only. Saved security reports are not deleted.')),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.tr('Batal'))),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.tr('Clear activity'))),
      ],
    ),
  );
  if (confirmed == true) await onClear();
}

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
  ValueChanged<ToolRunResult> onResult, {
  ActivityHistoryStore? activityStore,
  void Function(ActivityEvent event)? onActivity,
  FindingRepository? findingRepository,
  void Function(List<FindingRecord> findings)? onFindings,
  void Function(ToolRunResult result)? onReportSaved,
  void Function(Object error, StackTrace stack)? onReportSaveFailed,
}) async {
  final result = await showDialog<ToolRunResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ToolRunnerDialog(
      tool: tool,
      recentResults: recentResults,
      activityStore: activityStore,
      onActivity: onActivity,
      findingRepository: findingRepository,
      onFindings: onFindings,
      onReportSaved: onReportSaved,
      onReportSaveFailed: onReportSaveFailed,
    ),
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
