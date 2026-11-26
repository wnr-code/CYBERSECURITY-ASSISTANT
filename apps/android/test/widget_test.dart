import 'dart:async';
import 'dart:io';

import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:cybersecurity_assistant/core/assessment_execution_manager.dart';
import 'package:cybersecurity_assistant/core/local_result_store.dart';
import 'package:cybersecurity_assistant/core/package_manager.dart';
import 'package:cybersecurity_assistant/core/provider_registry.dart';
import 'package:cybersecurity_assistant/core/runtime_manager.dart';
import 'package:cybersecurity_assistant/core/security_findings.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:cybersecurity_assistant/core/tool_orchestrator.dart';
import 'package:cybersecurity_assistant/core/tool_registry.dart';
import 'package:cybersecurity_assistant/l10n/app_localizations.dart';
import 'package:cybersecurity_assistant/main.dart';
import 'package:cybersecurity_assistant/widgets/ai_shield_robot_mark.dart';
import 'package:cybersecurity_assistant/widgets/animated_splash_screen.dart';
import 'package:cybersecurity_assistant/widgets/catalog_screen.dart';
import 'package:cybersecurity_assistant/widgets/assessment_runner.dart';
import 'package:cybersecurity_assistant/widgets/dashboard_screen.dart';
import 'package:cybersecurity_assistant/widgets/digital_earth_hero.dart';
import 'package:cybersecurity_assistant/widgets/floating_terminal.dart';
import 'package:cybersecurity_assistant/widgets/market_brand_mark.dart';
import 'package:cybersecurity_assistant/widgets/market_screen.dart';
import 'package:cybersecurity_assistant/widgets/provider_details_dialog.dart';
import 'package:cybersecurity_assistant/widgets/tool_runner_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _UnusedPackageDownloader implements PackageDownloader {
  @override
  Future<DownloadedPackage> download(MarketPackage package, {required int maxBytes, required Duration timeout}) async {
    throw StateError('The catalog-only widget test does not initiate downloads.');
  }
}

class _MemorySecretBackend implements SecureStorageBackend {
  final values = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _MemoryResultHistory implements ResultHistoryStore {
  _MemoryResultHistory({this.loadResults});

  final Future<List<ToolRunResult>> Function()? loadResults;
  int loadCalls = 0;

  @override
  Future<int> save(ToolRunResult result, {String? assessmentId}) async => 1;

  @override
  Future<ToolRunResult?> loadReportById(String reportId) async => null;

  @override
  Future<List<ToolRunResult>> loadRecent({int limit = 30}) {
    loadCalls++;
    return loadResults?.call() ?? Future.value(const []);
  }

  @override
  Future<void> clear() async {}

  @override
  Future<void> close() async {}
}

class _CancellableAssessmentOrchestrator extends ToolOrchestrator {
  _CancellableAssessmentOrchestrator(this.started);

  final Completer<void> started;
  RuntimeCancellationToken? receivedToken;
  List<String> receivedToolIds = const [];
  int calls = 0;

  @override
  Future<ToolAvailability> availabilityForTool(String toolId) async => ToolAvailability(
        definition: toolById(toolId)!,
        status: ToolStatus.ready,
        compatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
        adapterRegistered: true,
        installed: true,
      );

  @override
  Future<AssessmentExecution> runAssessment({
    required String target,
    required Iterable<String> toolIds,
    required bool authorized,
    bool allowPrivateNetwork = false,
    bool includeResponseAnalysis = true,
    RuntimeCancellationToken? cancellationToken,
    void Function(AssessmentCheckOutcome outcome)? onOutcome,
  }) async {
    calls++;
    receivedToolIds = List.unmodifiable(toolIds);
    receivedToken = cancellationToken;
    if (!started.isCompleted) started.complete();
    await cancellationToken!.whenCancelled;
    const outcome = AssessmentCheckOutcome(
      toolId: 'dns_lookup',
      status: AssessmentCheckStatus.cancelled,
      error: 'Check cancelled.',
    );
    onOutcome?.call(outcome);
    final now = DateTime.now().toUtc();
    return AssessmentExecution(target: target, startedAt: now, completedAt: now, outcomes: [outcome]);
  }
}

class _CompletingAssessmentOrchestrator extends ToolOrchestrator {
  int calls = 0;

  @override
  Future<ToolAvailability> availabilityForTool(String toolId) async => ToolAvailability(
        definition: toolById(toolId)!,
        status: ToolStatus.ready,
        compatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
        adapterRegistered: true,
        installed: true,
      );

  @override
  Future<AssessmentExecution> runAssessment({
    required String target,
    required Iterable<String> toolIds,
    required bool authorized,
    bool allowPrivateNetwork = false,
    bool includeResponseAnalysis = true,
    RuntimeCancellationToken? cancellationToken,
    void Function(AssessmentCheckOutcome outcome)? onOutcome,
  }) async {
    calls++;
    final now = DateTime.now().toUtc();
    final result = ToolRunResult(
      toolId: 'dns_lookup',
      target: target,
      summary: 'Resolved 1 address.',
      details: const [],
      findings: const [],
      completedAt: now,
      authorizationConfirmed: authorized,
    );
    final outcome = AssessmentCheckOutcome(toolId: 'dns_lookup', status: AssessmentCheckStatus.completed, result: result);
    onOutcome?.call(outcome);
    return AssessmentExecution(target: target, startedAt: now, completedAt: now, outcomes: [outcome]);
  }
}

class _AssessmentWithGeneratedAnalysisOrchestrator extends ToolOrchestrator {
  @override
  Future<ToolAvailability> availabilityForTool(String toolId) async => ToolAvailability(
        definition: toolById(toolId)!,
        status: ToolStatus.ready,
        compatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
        adapterRegistered: true,
        installed: true,
      );

  @override
  Future<AssessmentExecution> runAssessment({
    required String target,
    required Iterable<String> toolIds,
    required bool authorized,
    bool allowPrivateNetwork = false,
    bool includeResponseAnalysis = true,
    RuntimeCancellationToken? cancellationToken,
    void Function(AssessmentCheckOutcome outcome)? onOutcome,
  }) async {
    final now = DateTime.now().toUtc();
    final selectedResult = ToolRunResult(
      toolId: 'dns_lookup',
      target: target,
      summary: 'Resolved one address.',
      details: const [],
      findings: const [],
      completedAt: now,
      authorizationConfirmed: authorized,
    );
    final analyzerResult = ToolRunResult(
      toolId: 'response_analyzer',
      target: target,
      summary: 'Response analysis completed.',
      details: const [],
      findings: const [],
      completedAt: now,
      authorizationConfirmed: false,
    );
    final selected = AssessmentCheckOutcome(
      toolId: 'dns_lookup',
      status: AssessmentCheckStatus.completed,
      result: selectedResult,
    );
    final generated = AssessmentCheckOutcome(
      toolId: 'response_analyzer',
      status: AssessmentCheckStatus.completed,
      result: analyzerResult,
    );
    onOutcome?.call(selected);
    return AssessmentExecution(
      target: target,
      startedAt: now,
      completedAt: now,
      outcomes: [selected, if (includeResponseAnalysis) generated],
    );
  }
}

class _CancellableToolOrchestrator extends ToolOrchestrator {
  _CancellableToolOrchestrator(this.started);

  final Completer<void> started;
  RuntimeCancellationToken? receivedToken;

  @override
  Future<ToolRunResult> execute(ToolInvocation invocation) async {
    receivedToken = invocation.cancellationToken;
    if (!started.isCompleted) started.complete();
    await invocation.cancellationToken!.whenCancelled;
    throw const RuntimeExecutionCancelled();
  }
}

FindingRecord _findingFixture({
  required String id,
  required String fingerprint,
  required String title,
  required String target,
  required String category,
  required FindingSeverity severity,
  required FindingStatus status,
}) {
  final at = DateTime.utc(2026, 11, 20);
  return FindingRecord(
    findingId: id,
    fingerprint: fingerprint,
    title: title,
    category: category,
    target: target,
    severity: severity,
    confidence: FindingConfidence.potential,
    status: status,
    description: 'Review this potential indicator.',
    evidence: const ['A bounded evidence marker was recorded.'],
    sourceReportKeys: const [],
    recommendation: 'Review the source report and configuration.',
    firstSeen: at,
    lastSeen: at,
    createdAt: at,
    updatedAt: at,
    sourceTool: 'http_headers',
    assessmentId: 'assessment-widget-fixture',
  );
}

void _useTallViewport(WidgetTester tester, {double width = 800}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _scrollListUntilVisible(WidgetTester tester, Finder list, Finder target, {double distance = 280}) async {
  for (var attempt = 0; attempt < 20 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(list, Offset(0, -distance));
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget, reason: 'The target should be reachable by scrolling the dashboard list.');
}

Widget _testApp() => CybersecurityAssistantApp(resultStore: _MemoryResultHistory());

void _installSecureStorageTestBackend(WidgetTester tester) {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const localAiCapabilityChannel = MethodChannel('org.cybersecurityassistant/local_ai_capabilities');
  const localAiRuntimeChannel = MethodChannel('org.cybersecurityassistant/local_ai_runtime');
  final values = <String, String>{};
  final testSupportDirectory = Directory.systemTemp.createTempSync('csa-widget-support-');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
    if (call.method == 'getApplicationSupportDirectory' || call.method == 'getTemporaryDirectory') {
      return testSupportDirectory.path;
    }
    return null;
  });
  messenger.setMockMethodCallHandler(localAiCapabilityChannel, (call) async => null);
  // App startup probes optional on-device inference. Complete that probe as
  // Not Ready immediately instead of leaving a three-second fake-async timer
  // behind in every widget test that mounts the production app shell.
  messenger.setMockMethodCallHandler(localAiRuntimeChannel, (call) async => null);
  addTearDown(() {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(localAiCapabilityChannel, null);
    messenger.setMockMethodCallHandler(localAiRuntimeChannel, null);
    if (testSupportDirectory.existsSync()) testSupportDirectory.deleteSync(recursive: true);
  });
  messenger.setMockMethodCallHandler(channel, (call) async {
    final arguments = call.arguments is Map ? Map<Object?, Object?>.from(call.arguments as Map) : <Object?, Object?>{};
    final key = arguments['key'] as String?;
    switch (call.method) {
      case 'read':
        return key == null ? null : values[key];
      case 'write':
        if (key != null && arguments['value'] is String) values[key] = arguments['value'] as String;
        return null;
      case 'delete':
        if (key != null) values.remove(key);
        return null;
      case 'containsKey':
        return key != null && values.containsKey(key);
      case 'readAll':
        return Map<String, String>.unmodifiable(values);
      case 'deleteAll':
        values.clear();
        return null;
      default:
        return null;
    }
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

Future<void> _pumpAfterTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder, {int attempts = 40}) async {
  for (var attempt = 0; attempt < attempts && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Finder _findCatalogUnavailableMessage() => find.byWidgetPredicate(
      (widget) => widget is Text && const {
        'Saat ini tidak ada pemeriksaan yang tersedia di perangkat ini.',
        'No checks are currently available on this device.',
        'Pemeriksaan kesiapan gagal; pemeriksaan terdampak disembunyikan.',
        'Readiness checks failed; affected checks are hidden.',
      }.contains(widget.data),
    );

String _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
    .where((value) => value.isNotEmpty)
    .join(' | ');

Future<void> _pumpUntilCatalogReady(WidgetTester tester) async {
  final busy = find.descendant(of: find.byType(CatalogScreen), matching: find.byType(LinearProgressIndicator));
  for (var attempt = 0; attempt < 100 && busy.evaluate().isNotEmpty; attempt++) {
    // The readiness chain includes real async filesystem work (Market state).
    // Give it bounded wall-clock time as well as advancing the test clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(busy, findsNothing,
      reason: 'Catalog readiness must finish within five seconds; otherwise expose the pending operation in test output.');
}

Future<void> _pumpApp(WidgetTester tester) async {
  // The active-assessment grid animation honors reduced motion, allowing
  // pumpAndSettle to settle deterministically like an accessibility user.
  tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
  _installSecureStorageTestBackend(tester);
  await tester.pumpWidget(_testApp());
  await tester.pumpAndSettle();
}

Future<void> _openCatalogFromDashboard(WidgetTester tester) async {
  await _tapPrimaryDestination(tester, 0);
  await _pumpAfterTransition(tester);
  final dashboardScroll = find.descendant(
    of: find.byKey(const ValueKey('dashboard-scroll-view')),
    matching: find.byType(Scrollable),
  ).first;
  await tester.scrollUntilVisible(find.text('Buka Katalog'), 260, scrollable: dashboardScroll);
  await tester.tap(find.text('Buka Katalog').first);
  await _pumpAfterTransition(tester);
}

Future<void> _tapPrimaryDestination(WidgetTester tester, int index) async {
  final bottomItem = find.byKey(ValueKey('bottom-navigation-$index'));
  if (bottomItem.evaluate().isNotEmpty) {
    await tester.tap(bottomItem);
    return;
  }
  const labels = ['Beranda', 'Assessment', 'Laporan', 'Pengaturan'];
  await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(labels[index])));
}

Future<void> _openConnectionsFromSettings(WidgetTester tester) async {
  await _tapPrimaryDestination(tester, 3);
  await tester.pumpAndSettle();
  final settingsScroll = find.descendant(
    of: find.byKey(const ValueKey('settings-scroll-view')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(find.text('Tes keterjangkauan endpoint'), 240, scrollable: settingsScroll);
  await tester.tap(find.text('Tes keterjangkauan endpoint'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dashboard follows the agreed Digital Earth and honest instrument hierarchy', (tester) async {
    _useTallViewport(tester, width: 390);
    await _pumpApp(tester);

    expect(find.byType(DigitalEarthHero), findsOneWidget);
    expect(find.byKey(const ValueKey('digital-earth-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('instrument-security-score')), findsOneWidget);
    expect(find.byKey(const ValueKey('instrument-risk-level')), findsOneWidget);
    expect(find.byKey(const ValueKey('instrument-scan-progress')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('instrument-security-score')), matching: find.text('Belum tersedia')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('instrument-risk-level')), matching: find.text('Belum dihitung')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('instrument-scan-progress')), matching: find.text('Tidak ada assessment yang berjalan')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('digital-earth-hero')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Ikhtisar Keamanan'), findsOneWidget);
  });

  testWidgets('Market provider marks use Cloudflare and Gemini brand artwork', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Row(children: [
          MarketBrandMark(providerId: 'cloudflare'),
          MarketBrandMark(providerId: 'gemini'),
          MarketBrandMark(providerId: 'local_ai'),
          AiShieldRobotMark(progress: .5),
        ]),
      ),
    ));
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect((images[0].image as AssetImage).assetName, 'assets/brands/cloudflare.png');
    expect((images[1].image as AssetImage).assetName, 'assets/brands/googlegemini.png');
    expect(find.byIcon(Icons.memory_rounded), findsOneWidget);
    expect(find.byType(AiShieldRobotMark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Market exposes provider readiness, the Local AI integration candidate, and installable data packages', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('open-market-button')));
    await _pumpAfterTransition(tester);
    final geminiProviderCard = find.byKey(const ValueKey('priority-provider-gemini'));
    await _pumpUntilFound(tester, geminiProviderCard);

    expect(find.text('Provider'), findsWidgets);
    expect(find.text('Paket'), findsOneWidget);
    expect(find.text('AI Models'), findsNothing);
    expect(geminiProviderCard, findsOneWidget,
        reason: 'Market must finish initialization and render provider cards. Text on screen: ${_renderedText(tester)}');
    expect(find.byKey(const ValueKey('priority-provider-cloudflare')), findsOneWidget);
    expect(find.byKey(const ValueKey('priority-provider-local_ai')), findsOneWidget);
    expect(find.text('Local AI'), findsOneWidget);
    expect(find.text('Not Ready — proses integrasi'), findsOneWidget);

    await tester.tap(find.text('Paket'));
    await _pumpAfterTransition(tester);
    expect(find.text('Security Assessment Evidence Guide'), findsOneWidget);
    expect(find.text('External Runtime Package (unsupported)'), findsNothing);
    expect(find.text('Sample Plugin (planned)'), findsNothing);
    expect(find.text('Local AI Model (planned)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Market only lists packages with a real installable artifact and hides unavailable features', (tester) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('market-widget-')))!;
    final manager = MarketPackageManager(
      catalog: bundledMarketCatalog,
      environment: const CompatibilityEnvironment(platform: 'Android'),
      downloader: _UnusedPackageDownloader(),
      supportDirectoryProvider: () async => directory,
    );
    try {
      await tester.runAsync(manager.initialize);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('id'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
        home: MarketScreen(packageManager: manager),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Market'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Provider'), findsNothing);
      expect(find.text('Paket'), findsWidgets);
      expect(find.text('AI Models'), findsNothing);
      expect(find.text('Security Assessment Evidence Guide'), findsOneWidget);
      expect(find.text('External Runtime Package (unsupported)'), findsNothing);
      expect(find.text('Sample Plugin (planned)'), findsNothing);
      expect(find.text('Local AI Model (planned)'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      manager.dispose();
      await tester.runAsync(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('animated splash renders the digital map, orbiting shield and four feature marks on compact screens', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: AnimatedSplashScreen(),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('splash-digital-world-and-circuits')), findsOneWidget);
    expect(find.byKey(const ValueKey('splash-animated-shield')), findsOneWidget);
    expect(find.text('ANALISIS · LINDUNGI · PERBAIKI'), findsOneWidget);
    expect(find.text('Keamanan terpadu'), findsOneWidget);
    expect(find.text('AI Expert'), findsOneWidget);
    expect(find.text('Tools lengkap'), findsOneWidget);
    expect(find.text('Analisis mendalam'), findsOneWidget);
    expect(find.text('Memuat aplikasi...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assessment presents multi-check target entry and explicit permission gate', (tester) async {
    final manager = AssessmentExecutionManager(orchestrator: ToolOrchestrator());
    addTearDown(manager.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: SingleChildScrollView(child: AssessmentRunner(executionManager: manager))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Assessment keamanan'), findsOneWidget);
    expect(find.text('Domain target atau URL HTTPS'), findsOneWidget);
    expect(find.text('Pemeriksaan yang dijalankan'), findsOneWidget);
    expect(find.text('Jalankan assessment'), findsOneWidget);
    expect(find.text('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'), findsOneWidget);
    expect(find.text('Izinkan target jaringan lokal/private'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AssessmentRunner receives an Orchestrator-generated response analyzer outcome', (tester) async {
    final manager = AssessmentExecutionManager(orchestrator: _AssessmentWithGeneratedAnalysisOrchestrator());
    addTearDown(manager.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(body: SingleChildScrollView(child: AssessmentRunner(executionManager: manager))),
    ));

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'owned.example');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.text('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'));
    await tester.pump();
    await tester.tap(find.text('Jalankan assessment'));
    await tester.pumpAndSettle();

    expect(manager.currentRun?.selectedToolIds, ['dns_lookup']);
    expect(manager.currentRun?.outcomes.map((outcome) => outcome.toolId), ['dns_lookup', 'response_analyzer']);
    expect(manager.currentRun?.progress.selectedCount, 1);
    expect(manager.currentRun?.progress.processedCount, 1);
    expect(find.text('Penganalisis Respons Keamanan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assessment displays a cancel action and reports a cancelled outcome', (tester) async {
    final started = Completer<void>();
    final orchestrator = _CancellableAssessmentOrchestrator(started);
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    addTearDown(manager.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: SingleChildScrollView(child: AssessmentRunner(executionManager: manager)),
      ),
    ));

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'owned.example');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.text('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'));
    await tester.pump();
    await tester.tap(find.text('Jalankan assessment'));
    await tester.pump();
    await started.future;

    expect(orchestrator.receivedToken, isNotNull);
    expect(manager.progress?.selectedCount, 1);
    expect(manager.progress?.processedCount, 0);
    final runId = manager.activeRun?.runId;
    expect(runId, isNotNull);
    expect(find.text('Batalkan pemeriksaan'), findsOneWidget);
    await tester.tap(find.text('Batalkan pemeriksaan'));
    await tester.pumpAndSettle();

    expect(orchestrator.receivedToken!.isCancelled, isTrue);
    expect(find.text('Pemeriksaan dibatalkan.'), findsOneWidget);
    expect(manager.currentRun?.runId, runId);
    expect(manager.currentRun?.isRunning, isFalse);
    expect(manager.currentRun?.wasCancelled, isTrue);
    expect(manager.currentRun?.progress.cancelledCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('result callback exceptions do not interrupt normal assessment completion or cleanup', (tester) async {
    final orchestrator = _CompletingAssessmentOrchestrator();
    final manager = AssessmentExecutionManager(
      orchestrator: orchestrator,
      onResult: (_) => throw StateError('Simulated result callback failure.'),
    );
    addTearDown(manager.dispose);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: SingleChildScrollView(child: AssessmentRunner(executionManager: manager)),
      ),
    ));

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'owned.example');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.text('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'));
    await tester.pump();
    await tester.tap(find.text('Jalankan assessment'));
    await tester.pumpAndSettle();

    expect(orchestrator.calls, 1);
    expect(manager.currentRun?.isRunning, isFalse);
    expect(manager.currentRun?.outcomes.single.status, AssessmentCheckStatus.completed);
    expect(find.text('Jalankan assessment'), findsOneWidget, reason: 'Runner state must be cleaned up after callback failures.');
    expect(find.text('Batalkan pemeriksaan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MainShell keeps one Assessment running across tabs and a recreated Runner can cancel it', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    _useTallViewport(tester, width: 390);

    final started = Completer<void>();
    final orchestrator = _CancellableAssessmentOrchestrator(started);
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: MainShell(
        resultStore: _MemoryResultHistory(),
        initialSavedResults: const [],
        assessmentExecutionManager: manager,
        locale: const Locale('id'),
      ),
    ));
    await tester.pumpAndSettle();

    await _tapPrimaryDestination(tester, 1);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'owned.example');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.text('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'));
    await tester.pump();
    await tester.tap(find.text('Jalankan assessment'));
    await tester.pump();
    await started.future;

    final originalRunId = manager.activeRun?.runId;
    expect(orchestrator.calls, 1);
    expect(orchestrator.receivedToolIds, ['dns_lookup']);
    expect(manager.progress?.processedCount, 0);

    final rejected = manager.startAssessment(
      target: 'second.example',
      toolIds: const ['tls_inspector'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    expect(rejected.accepted, isFalse);
    expect(orchestrator.calls, 1, reason: 'A second active Assessment must not create another Orchestrator run.');

    await _tapPrimaryDestination(tester, 0);
    await tester.pumpAndSettle();
    expect(manager.activeRun?.runId, originalRunId);
    await _scrollListUntilVisible(
      tester,
      find.byKey(const ValueKey('dashboard-scroll-view')),
      find.textContaining('owned.example · 0 / 1 pemeriksaan'),
      distance: 240,
    );
    expect(find.textContaining('owned.example · 0 / 1 pemeriksaan'), findsOneWidget,
        reason: 'The status visual uses the active run target and live progress from the application-owned manager.');

    await _tapPrimaryDestination(tester, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    expect(manager.activeRun?.runId, originalRunId);
    expect(find.text('Assessment sedang berjalan'), findsOneWidget);
    expect(find.text('Batalkan pemeriksaan'), findsOneWidget, reason: 'The recreated Runner controls the existing run.');
    expect(orchestrator.calls, 1, reason: 'Rebuilding the Runner must not start another assessment.');

    final cancelAssessment = find.text('Batalkan pemeriksaan');
    await tester.ensureVisible(cancelAssessment);
    await tester.tap(cancelAssessment);
    await tester.pumpAndSettle();
    expect(orchestrator.receivedToken?.isCancelled, isTrue);
    expect(manager.currentRun?.runId, originalRunId);
    expect(manager.currentRun?.wasCancelled, isTrue);
    expect(manager.currentRun?.progress.cancelledCount, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('MainShell teardown requests cancellation before releasing the application manager', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    _useTallViewport(tester, width: 390);

    final started = Completer<void>();
    final orchestrator = _CancellableAssessmentOrchestrator(started);
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: MainShell(
        resultStore: _MemoryResultHistory(),
        initialSavedResults: const [],
        assessmentExecutionManager: manager,
        locale: const Locale('id'),
      ),
    ));
    await tester.pumpAndSettle();
    await _tapPrimaryDestination(tester, 1);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'owned.example');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.text('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'));
    await tester.pump();
    await tester.tap(find.text('Jalankan assessment'));
    await tester.pump();
    await started.future;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(orchestrator.receivedToken?.isCancelled, isTrue);
    expect(manager.currentRun?.isRunning, isFalse);
    expect(manager.currentRun?.wasCancelled, isTrue);
    expect(manager.currentRun?.progress.cancelledCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('individual tool dialog can cancel its active execution', (tester) async {
    final started = Completer<void>();
    final orchestrator = _CancellableToolOrchestrator(started);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: ToolRunnerDialog(
        tool: toolById('dns_lookup')!,
        recentResults: const [],
        orchestrator: orchestrator,
      ),
    ));

    await tester.enterText(find.byType(TextField).first, 'owned.example');
    await tester.tap(find.text('Saya memiliki target ini atau mendapat izin untuk memeriksanya.'));
    await tester.pump();
    await tester.tap(find.text('Jalankan pemeriksaan'));
    await tester.pump();
    await started.future;

    expect(find.text('Batalkan pemeriksaan'), findsOneWidget);
    await tester.tap(find.text('Batalkan pemeriksaan'));
    await tester.pumpAndSettle();

    expect(orchestrator.receivedToken!.isCancelled, isTrue);
    expect(find.text('Pemeriksaan dibatalkan.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports remain separate while findings use independent records and source references', (tester) async {
    _useTallViewport(tester);
    final result = ToolRunResult(
      toolId: 'http_headers',
      target: 'owned.example',
      summary: 'Received HTTP 200 and inspected 2 response headers.',
      details: const ['HTTP 200', 'security headers inspected'],
      findings: const [
        SecurityFinding(
          title: 'Content-Security-Policy header not observed',
          severity: FindingSeverity.medium,
          confidence: FindingConfidence.potential,
          recommendation: 'Review whether a Content-Security-Policy is appropriate for this application.',
        ),
      ],
      completedAt: DateTime.utc(2026, 11, 23),
      authorizationConfirmed: true,
    );
    final independentFinding = findingRecordFromTool(
      finding: result.findings.single,
      result: result,
      sourceReportKey: activityResultKey(result.toolId, result.target, result.completedAt),
      assessmentId: 'assessment-widget-test',
    );
    String? openedSource;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: ReportsScreen(
          recentResults: [result],
          savedResults: [result],
          savedHistoryLoaded: true,
          storageBusy: false,
          storageError: null,
          onLoadSavedResults: () async {},
          onClearResults: () {},
          onClearSavedResults: () async {},
          onSaveResult: (_) async => true,
          findings: [independentFinding],
          findingsLoaded: true,
          onOpenFindingReport: (key) async => openedSource = key,
        ),
      ),
    ));

    expect(find.text('Laporan dan riwayat'), findsOneWidget);
    expect(find.text('Temuan'), findsOneWidget);
    await tester.tap(find.text('Temuan'));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('finding-${independentFinding.findingId}')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('finding-${independentFinding.findingId}')));
    await tester.pumpAndSettle();
    expect(find.text('Detail temuan'), findsOneWidget);
    expect(find.text('Pertama terlihat'), findsOneWidget);
    await tester.tap(find.text('Buka laporan sumber').last);
    await tester.pumpAndSettle();
    expect(openedSource, independentFinding.sourceReportKeys.single);
    expect(tester.takeException(), isNull);
  });

  testWidgets('independent findings support search, severity, status, target, category and status updates', (tester) async {
    _useTallViewport(tester);
    final findings = [
      _findingFixture(
        id: 'finding-alpha',
        fingerprint: '1111111111111111111111111111111111111111111111111111111111111111',
        title: 'Potential header issue',
        target: 'alpha.example',
        category: 'HTTP Security Headers',
        severity: FindingSeverity.high,
        status: FindingStatus.open,
      ),
      _findingFixture(
        id: 'finding-beta',
        fingerprint: '2222222222222222222222222222222222222222222222222222222222222222',
        title: 'Sensitive response indicator',
        target: 'beta.example',
        category: 'API Data Exposure',
        severity: FindingSeverity.info,
        status: FindingStatus.falsePositive,
      ),
    ];
    final updates = <(String, FindingStatus)>[];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: ReportsScreen(
          recentResults: const [],
          savedResults: const [],
          savedHistoryLoaded: true,
          storageBusy: false,
          storageError: null,
          onLoadSavedResults: () async {},
          onClearResults: () {},
          onClearSavedResults: () async {},
          onSaveResult: (_) async => true,
          findings: findings,
          findingsLoaded: true,
          onUpdateFindingStatus: (id, status) async {
            updates.add((id, status));
          },
        ),
      ),
    ));
    await tester.tap(find.text('Temuan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finding-finding-alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('finding-finding-beta')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('finding-search-filter')), 'alpha');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finding-finding-alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('finding-finding-beta')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('finding-search-filter')), '');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('finding-target-filter')), 'beta');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finding-finding-beta')), findsOneWidget);
    expect(find.byKey(const ValueKey('finding-finding-alpha')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('finding-target-filter')), '');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('finding-category-filter')), 'API');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finding-finding-beta')), findsOneWidget);
    expect(find.byKey(const ValueKey('finding-finding-alpha')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('finding-category-filter')), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('finding-severity-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TINGGI').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finding-finding-alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('finding-finding-beta')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('finding-severity-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semua tingkat keparahan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('finding-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Positif palsu').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finding-finding-beta')), findsOneWidget);
    expect(find.byKey(const ValueKey('finding-finding-alpha')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('finding-status-finding-beta')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diterima').last);
    await tester.pumpAndSettle();
    expect(updates, [('finding-beta', FindingStatus.accepted)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity timeline filters by date, target, tool type and status', (tester) async {
    _useTallViewport(tester);
    final now = DateTime.now().toUtc();
    final events = <ActivityEvent>[
      ActivityEvent(
        eventId: 'assessment-old',
        kind: ActivityKind.assessment,
        target: 'alpha.example',
        status: ActivityStatus.completed,
        startedAt: now.subtract(const Duration(days: 8)),
        finishedAt: now.subtract(const Duration(days: 8)).add(const Duration(minutes: 2)),
        summary: '2 checks completed, 0 failed, 0 cancelled.',
        findingCount: 0,
      ),
      ActivityEvent(
        eventId: 'dns-today',
        kind: ActivityKind.tool,
        toolId: 'dns_lookup',
        target: 'alpha.example',
        status: ActivityStatus.failed,
        startedAt: now,
        finishedAt: now.add(const Duration(seconds: 1)),
        summary: 'The check failed before producing a report.',
      ),
      ActivityEvent(
        eventId: 'http-today',
        kind: ActivityKind.tool,
        toolId: 'http_headers',
        target: 'alpha.example',
        status: ActivityStatus.completed,
        startedAt: now.add(const Duration(seconds: 3)),
        finishedAt: now.add(const Duration(seconds: 5)),
        summary: 'Received HTTP 200 and inspected 2 response headers.',
        findingCount: 1,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: ReportsScreen(
          recentResults: const [],
          savedResults: const [],
          savedHistoryLoaded: true,
          storageBusy: false,
          storageError: null,
          onLoadSavedResults: () async {},
          onClearResults: () {},
          onClearSavedResults: () async {},
          onSaveResult: (_) async => true,
          activityEvents: events,
          activityHistoryLoaded: true,
          onLoadActivities: () async {},
          onClearActivities: () async {},
        ),
      ),
    ));

    await tester.tap(find.text('Aktivitas'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-assessment-old')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-dns-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-http-today')), findsOneWidget);

    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-assessment-old')), findsNothing);
    expect(find.byKey(const ValueKey('activity-dns-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-http-today')), findsOneWidget);

    await tester.enterText(find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == 'Saring aktivitas berdasarkan target'), 'alpha');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pencarian DNS').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-dns-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-http-today')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('activity-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gagal').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-dns-today')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded splash hands off to dashboard while SQLite history is pending', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final initialization = Completer<List<ToolRunResult>>();
    final history = _MemoryResultHistory(loadResults: () => initialization.future);
    await tester.pumpWidget(CybersecurityAssistantApp(resultStore: history));
    expect(find.byKey(const ValueKey('animated-splash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1399));
    expect(find.byKey(const ValueKey('animated-splash')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-shell')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));

    expect(history.loadCalls, 1);
    expect(find.byKey(const ValueKey('main-shell')), findsOneWidget);
    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Memuat aplikasi...'), findsOneWidget);

    initialization.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('Beranda'), findsOneWidget);
    expect(history.loadCalls, 1);
  });

  testWidgets('database latency does not hold the dashboard behind a startup timeout', (tester) async {
    final initialization = Completer<List<ToolRunResult>>();
    final history = _MemoryResultHistory(loadResults: () => initialization.future);
    await tester.pumpWidget(CybersecurityAssistantApp(resultStore: history));
    await tester.pump(const Duration(milliseconds: 1400));

    expect(find.text('Beranda'), findsOneWidget);
    expect(history.loadCalls, 1);
    expect(initialization.isCompleted, isFalse);
  });

  testWidgets('floating mobile navigation has four destinations and a centered AI shortcut', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpApp(tester);

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Assessment'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Chat AI'), findsOneWidget);
    expect(find.text('Koneksi'), findsNothing);
    expect(find.byKey(const ValueKey('bottom-navigation-ai-chat')), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(ValueKey('bottom-navigation-$index')), findsOneWidget);
    }
    expect(find.text('Keamanan, kendali tetap di tangan Anda.'), findsOneWidget);
    final dashboardList = find.byKey(const ValueKey('dashboard-scroll-view'));
    await _scrollListUntilVisible(tester, dashboardList, find.text('STATUS ASSESSMENT'), distance: 240);
    expect(find.text('Belum ada Assessment tersimpan'), findsOneWidget);
    await _scrollListUntilVisible(tester, dashboardList, find.text('SKOR KEAMANAN'), distance: 240);
    expect(find.text('SKOR KEAMANAN'), findsOneWidget);
    expect(find.text('Belum dihitung'), findsOneWidget);
    expect(find.text('Tidak ada assessment yang berjalan'), findsOneWidget);
  });

  testWidgets('dashboard Session checks excludes response analysis while keeping its result visible', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    _useTallViewport(tester);

    final packageManager = MarketPackageManager.bundled();
    addTearDown(packageManager.dispose);
    final completedAt = DateTime.utc(2026, 11, 23);
    final recentResults = [
      ToolRunResult(
        toolId: 'dns_lookup',
        target: 'owned.example',
        summary: 'Resolved one address.',
        details: const ['A records: 192.0.2.10'],
        findings: const [],
        completedAt: completedAt,
      ),
      ToolRunResult(
        toolId: 'response_analyzer',
        target: 'owned.example',
        summary: 'Analysis completed.',
        details: const ['dns_lookup: Resolved one address.'],
        findings: const [],
        completedAt: completedAt,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: DashboardScreen(
          recentResults: recentResults,
          savedResultCount: 0,
          savedHistoryLoaded: true,
          findings: const [],
          findingsLoaded: true,
          findingsBusy: false,
          findingsError: null,
          activityEvents: const [],
          activityLoaded: true,
          activityBusy: false,
          activityError: null,
          marketPackageManager: packageManager,
          assessmentProgress: null,
          activeAssessmentTarget: null,
          onNavigateToTools: () {},
          onOpenCatalog: () {},
          onNavigateToReports: () {},
          onNavigateToFindings: (_) {},
          onOpenSecurityOverview: () {},
          onOpenAssistant: () {},
          onOpenActivity: (_) {},
          onOpenResult: (_) {},
          onSaveResult: (_) async => true,
        ),
      ),
    ));

    final dashboardList = find.byKey(const ValueKey('dashboard-scroll-view'));
    await _scrollListUntilVisible(tester, dashboardList, find.text('Penganalisis Respons Keamanan'), distance: 240);
    expect(find.text('Penganalisis Respons Keamanan'), findsOneWidget,
        reason: 'Analyzer remains available as a result; only the metric excludes it.');
    await _scrollListUntilVisible(tester, dashboardList, find.text('Pemeriksaan sesi'), distance: 240);
    final sessionMetric = find.ancestor(of: find.text('Pemeriksaan sesi'), matching: find.byType(Card)).first;
    expect(find.descendant(of: sessionMetric, matching: find.text('1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard analytics and recent activity use local repository records', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    _useTallViewport(tester);

    final activityStore = MemoryActivityHistoryStore();
    final startedAt = DateTime.utc(2026, 11, 22, 10);
    await activityStore.upsertActivity(ActivityEvent(
      eventId: 'assessment-dashboard-test',
      kind: ActivityKind.assessment,
      target: 'owned.example',
      status: ActivityStatus.completed,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(minutes: 1)),
      summary: '1 checks completed.',
      findingCount: 1,
    ));
    await activityStore.upsertActivity(ActivityEvent(
      eventId: 'tool-dashboard-test',
      kind: ActivityKind.tool,
      toolId: 'dns_lookup',
      parentEventId: 'assessment-dashboard-test',
      target: 'owned.example',
      status: ActivityStatus.completed,
      startedAt: startedAt.add(const Duration(seconds: 2)),
      finishedAt: startedAt.add(const Duration(seconds: 20)),
      summary: 'Resolved 1 address.',
    ));
    final findings = MemoryFindingRepository();
    await findings.saveObservedFindings([
      _findingFixture(
        id: 'finding-dashboard',
        fingerprint: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        title: 'Dashboard fixture finding',
        target: 'owned.example',
        category: 'HTTP Security Headers',
        severity: FindingSeverity.high,
        status: FindingStatus.open,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: MainShell(
        resultStore: _MemoryResultHistory(),
        activityStore: activityStore,
        findingRepository: findings,
        initialSavedResults: const [],
        locale: const Locale('id'),
      ),
    ));
    await tester.pumpAndSettle();

    final dashboardList = find.byKey(const ValueKey('dashboard-scroll-view'));
    await _scrollListUntilVisible(tester, dashboardList, find.text('STATUS ASSESSMENT'));
    expect(find.text('STATUS ASSESSMENT'), findsOneWidget);
    expect(find.textContaining('Findings yang dimuat: 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('security-status-hero')));
    await tester.pumpAndSettle();
    expect(find.text('Ikhtisar Keamanan'), findsOneWidget);
    expect(find.text('Peta jaringan belum tersedia'), findsOneWidget);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    await _scrollListUntilVisible(tester, dashboardList, find.textContaining('1 sesi assessment dalam data yang dimuat'));
    expect(find.textContaining('1 sesi assessment dalam data yang dimuat'), findsOneWidget);
    final securityHero = find.byKey(const ValueKey('security-status-hero'));
    expect(find.descendant(of: securityHero, matching: find.text('Selesai')), findsOneWidget);
    expect(find.descendant(of: securityHero, matching: find.textContaining('owned.example')), findsOneWidget);
    expect(find.descendant(of: securityHero, matching: find.textContaining('1 pemeriksaan selesai.')), findsOneWidget);
    expect(find.descendant(of: securityHero, matching: find.textContaining('Findings yang dimuat: 1')), findsOneWidget);
    await _scrollListUntilVisible(tester, dashboardList, find.textContaining('1 temuan dalam data yang dimuat'));
    expect(find.textContaining('1 temuan dalam data yang dimuat'), findsOneWidget);
    await _scrollListUntilVisible(tester, dashboardList, find.text('Pencarian DNS'));
    expect(find.text('Pencarian DNS'), findsOneWidget);
    expect(find.text('owned.example'), findsWidgets);
    expect(find.text('Aktivitas terbaru'), findsOneWidget);

    await _scrollListUntilVisible(tester, dashboardList, find.text('Buka Temuan'));
    await tester.tap(find.text('Buka Temuan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finding-search-filter')), findsOneWidget,
        reason: 'The Dashboard Findings shortcut opens directly on the Findings view.');
    var severityFilter = tester.widget<DropdownButton<FindingSeverity?>>(find.byKey(const ValueKey('finding-severity-filter')));
    expect(severityFilter.value, isNull);

    await _tapPrimaryDestination(tester, 0);
    await tester.pumpAndSettle();
    final homeList = find.byKey(const ValueKey('dashboard-scroll-view'));
    await _scrollListUntilVisible(tester, homeList, find.text('TINGGI  1'));
    await tester.tap(find.text('TINGGI  1'));
    await tester.pumpAndSettle();
    severityFilter = tester.widget<DropdownButton<FindingSeverity?>>(find.byKey(const ValueKey('finding-severity-filter')));
    expect(severityFilter.value, FindingSeverity.high,
        reason: 'Tapping an actual severity count opens Findings with that repository filter applied.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating navigation stays within a narrow phone viewport', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpApp(tester);

    expect(find.byKey(const ValueKey('bottom-navigation-ai-chat')), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(ValueKey('bottom-navigation-$index')), findsOneWidget);
    }
    final layoutError = tester.takeException();
    expect(layoutError, isNull, reason: layoutError?.toString());
  });

  testWidgets('center AI chat shortcut opens the existing secondary assistant route', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpApp(tester);
    expect(find.text('Chat AI'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-market-button')), findsOneWidget,
        reason: 'Market is directly reachable from the app bar without opening a catalog first.');

    await tester.tap(find.byKey(const ValueKey('bottom-navigation-ai-chat')));
    await _pumpAfterTransition(tester);
    final assistantRouteMarker = find.byKey(const ValueKey('assistant-info-button'));
    await _pumpUntilFound(tester, assistantRouteMarker);

    expect(assistantRouteMarker, findsOneWidget,
        reason: 'The AI chat shortcut should push the secondary Assistant route. Text on screen: ${_renderedText(tester)}');
    expect(find.byIcon(Icons.check_rounded), findsNothing,
        reason: 'No green check is shown unless the selected provider passed its connection test.');
  });

  testWidgets('AI assistant is a secondary module, not a primary navigation destination', (tester) async {
    await _pumpApp(tester);
    final moduleCard = find.text('Modul asisten AI');
    await tester.scrollUntilVisible(moduleCard, 180);
    await tester.tap(moduleCard);
    await _pumpAfterTransition(tester);
    final assistantRouteMarker = find.byKey(const ValueKey('assistant-info-button'));
    await _pumpUntilFound(tester, assistantRouteMarker);
    await _pumpUntilFound(tester, find.text('Kelola provider AI di Market'));

    expect(assistantRouteMarker, findsOneWidget,
        reason: 'Opening the assistant module should push its secondary route. Text on screen: ${_renderedText(tester)}');
    expect(find.text('Kelola provider AI di Market'), findsOneWidget);
    expect(find.text('Asisten'), findsNothing);
  });

  testWidgets('settings changes language without changing primary navigation', (tester) async {
    await _pumpApp(tester);
    await _tapPrimaryDestination(tester, 3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bahasa Indonesia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Assessment'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Connections'), findsNothing);
    expect(find.text('Assistant'), findsNothing);
  });

  testWidgets('Assessment is clean and Catalog is a separate destination', (tester) async {
    _useTallViewport(tester);
    await _pumpApp(tester);
    await _tapPrimaryDestination(tester, 1);
    await _pumpAfterTransition(tester);

    expect(find.text('Jalankan assessment'), findsOneWidget);
    expect(find.text('Katalog'), findsNothing);
    expect(find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == 'Cari alat keamanan'), findsNothing);

    await _openCatalogFromDashboard(tester);
    await _pumpUntilCatalogReady(tester);
    expect(find.text('ALAT KEAMANAN BAWAAN'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == 'Cari alat keamanan'), findsOneWidget);
    expect(find.text('Google Gemini'), findsNothing);
    expect(find.text('Cloudflare'), findsNothing);
    expect(find.text('Security Assessment Evidence Guide'), findsNothing,
        reason: 'Packages and provider setup now have one home: Market.');
    expect(find.text('Katalog alat'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters the tool registry by search text', (tester) async {
    _useTallViewport(tester);
    await _pumpApp(tester);
    await _tapPrimaryDestination(tester, 1);
    await tester.pumpAndSettle();
    await _openCatalogFromDashboard(tester);

    await _pumpUntilCatalogReady(tester);
    final tlsTool = find.byKey(const ValueKey('catalog-tool-tls_inspector'));
    if (tlsTool.evaluate().isEmpty) {
      expect(_findCatalogUnavailableMessage(), findsOneWidget,
          reason: 'Tools that are not ready for the current test platform are intentionally hidden. Text on screen: ${_renderedText(tester)}');
      return;
    }

    final catalogSearch = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == 'Cari alat keamanan',
    );
    await tester.enterText(catalogSearch, 'TLS');
    await tester.pump();

    expect(find.text('SSL/TLS Inspector'), findsOneWidget);
    expect(find.text('DNS Lookup'), findsNothing);
  });

  testWidgets('built-in catalog details use Built-in capability and hand off to Assessment', (tester) async {
    _useTallViewport(tester);
    await _pumpApp(tester);
    await _openCatalogFromDashboard(tester);
    await _pumpUntilCatalogReady(tester);
    final dnsTool = find.byKey(const ValueKey('catalog-tool-dns_lookup'));
    if (dnsTool.evaluate().isEmpty) {
      expect(
        _findCatalogUnavailableMessage(),
        findsOneWidget,
        reason: 'The catalog hides checks that are not ready on the current test platform. Text on screen: ${_renderedText(tester)}',
      );
      return;
    }
    await tester.tap(find.text('DNS Lookup'));
    await tester.pumpAndSettle();

    expect(find.text('Fungsi dan persyaratan'), findsOneWidget);
    expect(find.text('Bawaan'), findsWidgets);
    expect(find.text('Pasang'), findsNothing);
    await tester.tap(find.text('Buka Assessment'));
    await tester.pumpAndSettle();
    expect(find.text('Jalankan assessment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings endpoint page contains only the working unauthenticated reachability check', (tester) async {
    await _pumpApp(tester);
    await _openConnectionsFromSettings(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Keterjangkauan endpoint'), findsOneWidget);
    expect(find.text('Uji endpoint HTTPS'), findsOneWidget);
    expect(find.byKey(const ValueKey('connections-open-market')), findsNothing);
    expect(find.text('Google Gemini'), findsNothing);
    expect(find.text('OpenAI'), findsNothing);
    expect(find.text('Local AI'), findsNothing);
    expect(find.text('Other provider references'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider details stores a masked credential without making a provider request', (tester) async {
    final backend = _MemorySecretBackend();
    final credentialStore = SecureCredentialStore(backend: backend);
    final provider = providerRegistry.firstWhere((item) => item.id == 'openai');

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ProviderDetailsDialog(provider: provider, credentialStore: credentialStore),
              ),
              child: const Text('Open details'),
            )),
      ),
    ));

    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    final storeCredentialButton = find.widgetWithText(OutlinedButton, 'Store API key');
    await tester.ensureVisible(storeCredentialButton);
    await tester.tap(storeCredentialButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'test-key-never-send');
    expect(tester.widget<TextField>(find.byType(TextField).last).obscureText, isTrue);
    await tester.ensureVisible(find.text('Save securely'));
    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();

    expect(backend.values.values, contains('test-key-never-send'));
    expect(find.text('Credential stored locally. No provider request was made.'), findsOneWidget);
    expect(find.text('test-key-never-send'), findsNothing);

    final checkStatusButton = find.text('Check stored status');
    await tester.ensureVisible(checkStatusButton);
    await tester.tap(checkStatusButton);
    await tester.pumpAndSettle();
    expect(find.text('Credential storage status: present'), findsOneWidget);
    expect(find.text('A credential is stored; its value was not displayed.'), findsOneWidget);

    await tester.ensureVisible(find.text('Delete').first);
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(backend.values, isEmpty);
    expect(find.text('Credential deleted.'), findsOneWidget);
  });

  testWidgets('Edge Panel opens the in-app terminal and retains its session across tabs and minimization', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('Buka Edge Panel'));
    await tester.pumpAndSettle();
    expect(find.text('Edge Panel'), findsOneWidget);
    expect(find.textContaining('Belum ada provider yang terhubung'), findsOneWidget);
    expect(find.text('Assessment'), findsWidgets);
    expect(find.text('Laporan'), findsWidgets);
    expect(find.text('Pengaturan'), findsWidgets);
    expect(find.text('Katalog alat keamanan'), findsNothing);
    expect(find.text('Market · provider dan paket'), findsNothing);

    await tester.tap(find.text('Terminal Mengambang'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingTerminal), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'help');
    await tester.tap(find.byTooltip('Jalankan perintah'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Perintah yang didukung: help'), findsOneWidget);

    await _tapPrimaryDestination(tester, 2);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingTerminal), findsOneWidget);
    expect(find.textContaining('Perintah yang didukung: help'), findsOneWidget);

    await tester.tap(find.byTooltip('Minimalkan terminal'));
    await tester.pumpAndSettle();
    expect(find.text('Terminal diminimalkan'), findsOneWidget);
    await tester.tap(find.text('Terminal diminimalkan'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingTerminal), findsOneWidget);
    expect(find.textContaining('Perintah yang didukung: help'), findsOneWidget);

    await tester.tap(find.byTooltip('Keluar dari terminal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingTerminal), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requires current authorization and rejects invalid connection URLs', (tester) async {
    await _pumpApp(tester);
    await _openConnectionsFromSettings(tester);

    final connectionButton = find.widgetWithText(FilledButton, 'Uji koneksi');
    final authorization = find.descendant(
      of: find.byType(ConnectionsScreen),
      matching: find.byType(CheckboxListTile),
    ).first;
    final connectionScroll = find.descendant(
      of: find.byType(ConnectionsScreen),
      matching: find.byType(Scrollable),
    ).first;
    Future<void> confirmCurrentEndpoint() async {
      await tester.scrollUntilVisible(authorization, 100, scrollable: connectionScroll);
      await tester.drag(connectionScroll, const Offset(0, 160));
      await tester.pumpAndSettle();
      await tester.tap(authorization);
      await tester.pump();
    }

    await tester.enterText(find.byType(TextField).first, 'http://example.com');
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNull);

    await confirmCurrentEndpoint();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNotNull);
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Uji koneksi'));
    await tester.pump();
    expect(find.text('Masukkan URL HTTPS valid tanpa kredensial, kueri, atau fragmen.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'https://example.com/?token=secret');
    await tester.pump();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNull);
    await confirmCurrentEndpoint();
    expect(tester.widget<FilledButton>(connectionButton).onPressed, isNotNull);
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Uji koneksi'));
    await tester.pump();
    expect(find.text('Masukkan URL HTTPS valid tanpa kredensial, kueri, atau fragmen.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'https://example.com:not-a-port');
    await confirmCurrentEndpoint();
    await tester.ensureVisible(connectionButton);
    await tester.tap(find.text('Uji koneksi'));
    await tester.pump();
    expect(find.text('Masukkan URL HTTPS valid tanpa kredensial, kueri, atau fragmen.'), findsOneWidget);
  });
}
