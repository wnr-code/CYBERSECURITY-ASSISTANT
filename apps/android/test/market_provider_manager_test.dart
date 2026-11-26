import 'dart:convert';
import 'dart:io';
import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:cybersecurity_assistant/core/ai_provider_manager.dart';
import 'package:cybersecurity_assistant/core/market_provider_manager.dart';
import 'package:cybersecurity_assistant/core/provider_registry.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:cybersecurity_assistant/l10n/app_localizations.dart';
import 'package:cybersecurity_assistant/widgets/cloudflare_dashboard_screen.dart';
import 'package:cybersecurity_assistant/widgets/market_provider_detail_screen.dart';
import 'package:cybersecurity_assistant/widgets/market_provider_dialog.dart';
import 'package:cybersecurity_assistant/widgets/local_ai_diagnostic_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _MemorySecureStore implements SecureStorageBackend {
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

class _CloudflareTransport implements CloudflareTokenTransport {
  CloudflareVerificationResponse response = CloudflareVerificationResponse(
    statusCode: 200,
    body: utf8.encode(jsonEncode({'success': true, 'result': {'status': 'active'}})),
  );
  String? lastToken;
  int requests = 0;
  @override
  Future<CloudflareVerificationResponse> verify(String token) async {
    requests++;
    lastToken = token;
    return response;
  }
}

class _CloudflareReadTransport implements CloudflareReadTransport {
  final Map<String, CloudflareApiResponse> responses = {};
  final List<Uri> requests = [];
  String? lastToken;

  @override
  Future<CloudflareApiResponse> get(Uri uri, String token) async {
    requests.add(uri);
    lastToken = token;
    return responses[uri.path] ?? CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({'success': true, 'result': []})),
    );
  }
}

class _AiTransport implements AiHttpTransport {
  AiHttpResponse getResponse = AiHttpResponse(200, utf8.encode(jsonEncode({'name': 'models/gemini-3.5-flash-lite'})));
  int getRequests = 0;
  int postRequests = 0;
  @override
  Future<AiHttpResponse> get(Uri uri, Map<String, String> headers) async {
    getRequests++;
    expect(uri.host, 'generativelanguage.googleapis.com');
    expect(uri.query, isEmpty);
    expect(headers.keys, contains('x-goog-api-key'));
    return getResponse;
  }
  @override
  Future<AiHttpResponse> post(Uri uri, Map<String, String> headers, List<int> body) async {
    postRequests++;
    return const AiHttpResponse(500, []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capabilityChannel = MethodChannel('org.cybersecurityassistant/local_ai_capabilities');
  late _MemorySecureStore storage;
  late SecureCredentialStore credentials;
  late _CloudflareTransport cloudflare;
  late _CloudflareReadTransport cloudflareReads;
  late MemoryActivityHistoryStore activityStore;
  late _AiTransport geminiTransport;
  late AiProviderManager aiProviders;
  late MarketProviderManager manager;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      capabilityChannel,
      (_) async => null,
    );
    storage = _MemorySecureStore();
    credentials = SecureCredentialStore(backend: storage);
    cloudflare = _CloudflareTransport();
    cloudflareReads = _CloudflareReadTransport();
    activityStore = MemoryActivityHistoryStore();
    geminiTransport = _AiTransport();
    aiProviders = AiProviderManager(
      credentialStore: credentials,
      adapters: [GeminiAiProviderAdapter(credentialStore: credentials, transport: geminiTransport)],
    );
    manager = MarketProviderManager(
      credentials: credentials,
      configuration: ProviderConfigurationStore(storage),
      aiProviders: aiProviders,
      cloudflareTransport: cloudflare,
      cloudflareReadTransport: cloudflareReads,
      activityStore: activityStore,
      localAiProbe: const LocalAiCapabilityProbe(channel: capabilityChannel),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(capabilityChannel, null);
    manager.dispose();
    aiProviders.close();
  });

  test('initial status is truthful: bundled providers installed, Local AI not ready', () async {
    await manager.initialize();
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.installed);
    expect(manager.statusFor('gemini'), ManagedProviderStatus.installed);
    expect(manager.statusFor('local_ai'), ManagedProviderStatus.notReady);
    expect(manager.localAiCapabilities, isNull);
    expect(cloudflare.requests, 0);
    expect(geminiTransport.getRequests, 0);
  });

  testWidgets('Local AI physical-device diagnostic report is localized in Indonesian', (tester) async {
    const capabilityChannel = MethodChannel('org.cybersecurityassistant/local_ai_capabilities');
    const runtimeChannel = MethodChannel('org.cybersecurityassistant/local_ai_runtime');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(capabilityChannel, (call) async => {
      'supportedAbis': ['arm64-v8a'],
      'availableRamBytes': 2048,
      'availableStorageBytes': 4096,
      'installedModelCount': 0,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(runtimeChannel, (call) async => {
      'runtimeLoaded': true,
      'abi': 'arm64-v8a',
      'pinnedModelRepository': 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
      'pinnedModelRevision': '91cad51170dc346986eccefdc2dd33a9da36ead9',
      'pinnedModelLicense': 'Apache-2.0',
      'modelLoaded': false,
      'installedModels': [],
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(capabilityChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(runtimeChannel, null);
    });

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('id'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(body: LocalAiDiagnosticAction(status: ManagedProviderStatus.notReady)),
    ));
    await tester.tap(find.byKey(const ValueKey('local-ai-diagnostic-test')));
    await tester.pumpAndSettle();
    expect(find.text('Diagnostik Local AI'), findsOneWidget);
    await tester.tap(find.text('Jalankan diagnostik'));
    await tester.pumpAndSettle();

    final report = tester.widget<SelectableText>(find.byType(SelectableText).last).data!;
    expect(report, contains('ABI perangkat: LULUS'));
    expect(report, contains('Kesiapan: BELUM SIAP'));
    expect(report, contains('Integritas GGUF terpasang: TERBLOKIR'));
    expect(report, contains('metadata penerbit resmi dan byte GGUF sebenarnya harus lulus pemeriksaan unduhan di dalam aplikasi'));
    expect(report, isNot(contains('Device ABI:')));
  });

  testWidgets('provider detail screens separate configuration and accurately label unavailable Local AI actions', (tester) async {
    const runtimeChannel = MethodChannel('org.cybersecurityassistant/local_ai_runtime');
    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(runtimeChannel, (_) async => null);
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async => Directory.systemTemp.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(runtimeChannel, null);
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await manager.initialize();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: MarketProviderDetailScreen(providerId: 'cloudflare', manager: manager),
    ));
    expect(find.text('Account Configuration'), findsWidgets);
    expect(find.text('Permissions & Capabilities'), findsOneWidget);
    expect(find.textContaining('Read-only capabilities: GET /user/tokens/verify, GET /accounts, GET /zones, and GET /zones/{zone_id}.'), findsOneWidget);
    expect(find.text('Test Connection'), findsOneWidget);
    final connectBeforeConfiguration = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Test Connection'));
    expect(connectBeforeConfiguration.onPressed, isNull);
    expect(find.text('Open Dashboard'), findsNothing);

    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    await tester.pumpAndSettle();
    final connectAfterConfiguration = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Test Connection'));
    expect(connectAfterConfiguration.onPressed, isNotNull);
    expect(find.text('Credential saved on this device. Run Test Connection to verify it.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Test Connection'));
    await tester.pumpAndSettle();
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.connected);
    expect(find.text('Test Connection'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: MarketProviderDetailScreen(providerId: 'gemini', manager: manager),
    ));
    expect(find.text('Model Information'), findsOneWidget);
    expect(find.text('Data & Privacy'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: MarketProviderDetailScreen(providerId: 'local_ai', manager: manager),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    for (final section in ['Device Compatibility', 'Runtime Information', 'Model Catalog', 'Storage Management']) {
      expect(find.text(section), findsOneWidget);
    }
    expect(find.text('Not Ready: the runtime, compatible model, and successful local inference are not all available.'), findsOneWidget);
    expect(find.textContaining('The source-built CPU-only ARM64 APK passed static audit, which does not prove this phone can load the model or infer.'), findsOneWidget);
    expect(find.textContaining('Pinned llama.cpp source commit:'), findsOneWidget);
    expect(find.textContaining('The Qwen2.5 1.5B Instruct Q4_K_M candidate is pinned to an immutable Qwen repository revision.'), findsOneWidget);
    final installModel = tester.widget<OutlinedButton>(find.byKey(const ValueKey('local-ai-install-model')));
    expect(installModel.onPressed, isNotNull, reason: 'The APK must fetch and check official metadata before enabling native load.');
    expect(find.text('Offline Inference Test'), findsOneWidget);
    final diagnostic = tester.widget<OutlinedButton>(find.byKey(const ValueKey('local-ai-diagnostic-test')));
    expect(diagnostic.onPressed, isNotNull);
    await tester.ensureVisible(find.byKey(const ValueKey('local-ai-diagnostic-test')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('local-ai-diagnostic-test')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Local AI Diagnostic Test'), findsOneWidget);
    expect(manager.statusFor('local_ai'), ManagedProviderStatus.notReady);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Local AI Diagnostic Test stays available for NOT READY and READY provider statuses', (tester) async {
    for (final status in [ManagedProviderStatus.notReady, ManagedProviderStatus.connected]) {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
        home: Scaffold(body: LocalAiDiagnosticAction(status: status)),
      ));
      final action = tester.widget<OutlinedButton>(find.byKey(const ValueKey('local-ai-diagnostic-test')));
      expect(action.onPressed, isNotNull, reason: 'Diagnostic action must remain enabled when status is $status');
      await tester.tap(find.byKey(const ValueKey('local-ai-diagnostic-test')));
      await tester.pumpAndSettle();
      expect(find.text('Local AI Diagnostic Test'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Market configuration dialogs persist Cloudflare token and Gemini key before testing connections', (tester) async {
    await manager.initialize();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(
        body: Builder(builder: (context) => Column(children: [
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => MarketProviderDialog(providerId: 'cloudflare', manager: manager),
            ),
            child: const Text('Open Cloudflare configuration'),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => MarketProviderDialog(providerId: 'gemini', manager: manager),
            ),
            child: const Text('Open Gemini configuration'),
          ),
        ])),
      ),
    ));

    await tester.tap(find.text('Open Cloudflare configuration'));
    await tester.pumpAndSettle();
    final cloudflareFields = find.byType(TextField);
    expect(cloudflareFields, findsNWidgets(2));
    await tester.enterText(cloudflareFields.at(0), 'cloudflare-user-token-secret');
    await tester.enterText(cloudflareFields.at(1), 'aabbccddeeff00112233445566778899');
    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();
    expect(await credentials.read(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken), 'cloudflare-user-token-secret');
    expect(manager.cloudflareAccountId, 'aabbccddeeff00112233445566778899');
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.disconnected,
        reason: 'Saving is local; the provider must still pass its separate connection test.');
    expect(cloudflare.requests, 0);
    expect(find.text('Credential saved securely. No provider request was made.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Gemini configuration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'AIzaSyExample_Key-0123456789');
    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();
    expect(await credentials.read(providerId: 'gemini', kind: SecureCredentialKind.apiKey), 'AIzaSyExample_Key-0123456789');
    expect(manager.geminiConfigured, isTrue);
    expect(manager.statusFor('gemini'), ManagedProviderStatus.disconnected,
        reason: 'Saving is local; the Gemini model-access check is separate.');
    expect(geminiTransport.getRequests, 0);
    expect(geminiTransport.postRequests, 0);
    expect(tester.takeException(), isNull);
  });

  test('Cloudflare configuration validates account ID and saves token without network calls', () async {
    await manager.initialize();
    await expectLater(
      manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret', accountId: 'bad-id'),
      throwsA(isA<MarketProviderException>()),
    );
    expect(await credentials.read(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken), isNull);
    await manager.saveCloudflareConfiguration(
      token: 'cloudflare-user-token-secret',
      accountId: 'AABBCCDDEEFF00112233445566778899',
    );
    expect(manager.cloudflareConfigured, isTrue);
    expect(manager.cloudflareAccountId, 'aabbccddeeff00112233445566778899');
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.disconnected);
    expect(cloudflare.requests, 0);
  });

  test('Cloudflare Test Connection validates token status only and leaves service permissions to read checks', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    await manager.testConnection('cloudflare');
    expect(cloudflare.lastToken, 'cloudflare-user-token-secret');
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.connected);
    expect(manager.messageFor('cloudflare'), contains('DNS records, Workers'));
    expect(manager.cloudflareLastCheckedAt, isNotNull);
    expect(manager.cloudflareLastCheckSucceeded, isTrue);
  });

  test('Cloudflare read transport rejects any destination or path outside the exact GET allowlist', () async {
    var constructedClient = false;
    final transport = IoCloudflareReadTransport(clientFactory: () {
      constructedClient = true;
      throw StateError('Network client must not be created for blocked URLs.');
    });
    await expectLater(
      transport.get(Uri.https('api.cloudflare.com', '/client/v4/zones/11223344556677889900aabbccddeeff/dns_records'), 'secret'),
      throwsA(isA<MarketProviderException>()),
    );
    await expectLater(
      transport.get(Uri.https('example.com', '/client/v4/accounts'), 'secret'),
      throwsA(isA<MarketProviderException>()),
    );
    expect(constructedClient, isFalse);
  });

  test('Cloudflare account and zone reads are gated by token verification, parsed safely, and persisted to Activity Timeline', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(
      token: 'cloudflare-user-token-secret',
      accountId: 'aabbccddeeff00112233445566778899',
    );
    await expectLater(manager.loadCloudflareAccounts(), throwsA(isA<MarketProviderException>()));
    expect(cloudflareReads.requests, isEmpty);

    await manager.testConnection('cloudflare');
    cloudflareReads.responses['/client/v4/accounts'] = CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({
        'success': true,
        'result': [{'id': 'aabbccddeeff00112233445566778899', 'name': 'Real Example Account', 'type': 'standard'}],
        'result_info': {'total_count': 1},
      })),
    );
    cloudflareReads.responses['/client/v4/zones'] = CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({
        'success': true,
        'result': [{
          'id': '11223344556677889900aabbccddeeff',
          'name': 'example.org',
          'status': 'active',
          'type': 'full',
          'account': {'id': 'aabbccddeeff00112233445566778899', 'name': 'Real Example Account'},
        }],
        'result_info': {'total_count': 1},
      })),
    );
    cloudflareReads.responses['/client/v4/zones/11223344556677889900aabbccddeeff'] = CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({
        'success': true,
        'result': {
          'id': '11223344556677889900aabbccddeeff',
          'name': 'example.org',
          'status': 'active',
          'type': 'full',
          'account': {'id': 'aabbccddeeff00112233445566778899', 'name': 'Real Example Account'},
          'name_servers': ['ns1.example.net', 'ns2.example.net'],
          'created_on': '2024-01-01T00:00:00Z',
          'paused': false,
        },
      })),
    );

    final accounts = await manager.loadCloudflareAccounts();
    final zones = await manager.loadCloudflareZones(accountId: manager.cloudflareAccountId);
    final details = await manager.loadCloudflareZoneDetails(zones.single.id);

    expect(cloudflareReads.lastToken, 'cloudflare-user-token-secret');
    expect(cloudflareReads.requests.map((uri) => uri.queryParameters['account.id']).whereType<String>(), contains(manager.cloudflareAccountId));
    expect(cloudflareReads.requests.every((uri) => uri.host == 'api.cloudflare.com' && uri.scheme == 'https'), isTrue);
    expect(accounts.single.name, 'Real Example Account');
    expect(zones.single.name, 'example.org');
    expect(manager.cloudflareAccountsAccess, CloudflareAccessState.allowed);
    expect(manager.cloudflareZonesAccess, CloudflareAccessState.allowed);
    expect(details.nameServers, ['ns1.example.net', 'ns2.example.net']);
    expect(manager.cloudflareZoneDetailAccess, CloudflareAccessState.allowed);
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.connected);

    final events = await activityStore.loadActivities();
    expect(events, hasLength(3));
    expect(events.map((event) => event.toolId), containsAll(['cloudflare_accounts', 'cloudflare_zones', 'cloudflare_zone_detail']));
    expect(events.every((event) => event.target == 'api.cloudflare.com' && event.status == ActivityStatus.completed), isTrue);
    expect(events.any((event) => event.summary?.contains('example.org') == true), isFalse);
  });

  testWidgets('Cloudflare dashboard panel displays fetched accounts and opens a read-only zone detail', (tester) async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    await manager.testConnection('cloudflare');
    cloudflareReads.responses['/client/v4/accounts'] = CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({
        'success': true,
        'result': [{'id': 'aabbccddeeff00112233445566778899', 'name': 'Live Account', 'type': 'standard'}],
        'result_info': {'total_count': 1},
      })),
    );
    cloudflareReads.responses['/client/v4/zones'] = CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({
        'success': true,
        'result': [{'id': '11223344556677889900aabbccddeeff', 'name': 'live.example', 'status': 'active', 'type': 'full'}],
        'result_info': {'total_count': 1},
      })),
    );
    cloudflareReads.responses['/client/v4/zones/11223344556677889900aabbccddeeff'] = CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({
        'success': true,
        'result': {
          'id': '11223344556677889900aabbccddeeff',
          'name': 'live.example',
          'status': 'active',
          'type': 'full',
          'name_servers': ['ns1.live.example'],
          'paused': false,
        },
      })),
    );

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: Scaffold(body: SingleChildScrollView(child: CloudflareReadOnlyPanel(manager: manager))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Live Account'), findsOneWidget);
    expect(find.text('live.example'), findsOneWidget);
    expect(find.text('Read access confirmed by API'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ListTile, 'live.example'));
    await tester.pumpAndSettle();
    expect(find.text('ns1.live.example'), findsOneWidget);
    expect(find.text('Selected zone detail access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Cloudflare zone permission denial stays distinct from active-token status and is audited', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    await manager.testConnection('cloudflare');
    cloudflareReads.responses['/client/v4/zones'] = const CloudflareApiResponse(statusCode: 403, body: []);

    await expectLater(manager.loadCloudflareZones(), throwsA(isA<MarketProviderException>()));

    expect(manager.cloudflareZonesAccess, CloudflareAccessState.denied);
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.connected);
    expect(manager.cloudflareReadError, contains('minimum read permission'));
    final event = (await activityStore.loadActivities()).single;
    expect(event.status, ActivityStatus.failed);
    expect(event.summary, 'Cloudflare API read was rejected or unavailable.');
  });

  test('Cloudflare 401 authentication and 429 rate limits are distinct from 403 permission denial', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');

    for (final scenario in [
      (statusCode: 401, message: 'rejected the saved token', status: ManagedProviderStatus.error),
      (statusCode: 429, message: 'rate limit', status: ManagedProviderStatus.connected),
    ]) {
      await manager.testConnection('cloudflare');
      cloudflareReads.responses['/client/v4/accounts'] = CloudflareApiResponse(statusCode: scenario.statusCode, body: const []);
      await expectLater(manager.loadCloudflareAccounts(), throwsA(isA<MarketProviderException>()));
      expect(manager.cloudflareAccountsAccess, CloudflareAccessState.error);
      expect(manager.cloudflareReadError, contains(scenario.message));
      expect(manager.statusFor('cloudflare'), scenario.status);
    }
  });

  test('Cloudflare text rejects control and bidirectional override characters before display', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    await manager.testConnection('cloudflare');
    cloudflareReads.responses['/client/v4/accounts'] = CloudflareApiResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({
        'success': true,
        'result': [{'id': 'aabbccddeeff00112233445566778899', 'name': 'account\u202Ehidden'}],
      })),
    );

    await expectLater(manager.loadCloudflareAccounts(), throwsA(isA<MarketProviderException>()));
    expect(manager.cloudflareAccounts, isEmpty);
    expect(manager.cloudflareReadError, isNot(contains('hidden')));
  });

  test('Cloudflare API server errors are reported distinctly and do not become permission denials', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    await manager.testConnection('cloudflare');
    cloudflareReads.responses['/client/v4/accounts'] = const CloudflareApiResponse(statusCode: 503, body: []);

    await expectLater(manager.loadCloudflareAccounts(), throwsA(isA<MarketProviderException>()));

    expect(manager.cloudflareAccountsAccess, CloudflareAccessState.error);
    expect(manager.cloudflareAccountsAccess, isNot(CloudflareAccessState.denied));
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.connected);
    expect(manager.cloudflareReadError, contains('server problem'));
  });

  test('simultaneous Cloudflare reads are serialized before asynchronous preflight', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    await manager.testConnection('cloudflare');

    final firstRead = manager.loadCloudflareAccounts();
    final competingRead = manager.loadCloudflareZones();
    await expectLater(competingRead, throwsA(isA<MarketProviderException>()));
    expect(await firstRead, isEmpty);
    expect(cloudflareReads.requests, hasLength(1));
    expect(cloudflareReads.requests.single.path, '/client/v4/accounts');
  });

  test('Cloudflare invalid token fails closed and secret never enters status/error text', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret');
    cloudflare.response = CloudflareVerificationResponse(
      statusCode: 200,
      body: utf8.encode(jsonEncode({'success': false, 'result': {'status': 'expired'}})),
    );
    await expectLater(manager.testConnection('cloudflare'), throwsA(isA<MarketProviderException>()));
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.error);
    expect(manager.messageFor('cloudflare'), isNot(contains('cloudflare-user-token-secret')));
    expect(manager.cloudflareLastCheckedAt, isNotNull);
    expect(manager.cloudflareLastCheckSucceeded, isFalse);
  });

  test('Gemini setup links preserve the official AI Studio entry points', () {
    expect(MarketProviderManager.geminiStudioGettingStartedDocs.toString(), 'https://aistudio.google.com/docs/get-started');
    expect(MarketProviderManager.geminiAiStudioDocsIndex.toString(), 'https://aistudio.google.com/llms.txt');
    expect(MarketProviderManager.geminiKeyDocs.host, 'ai.google.dev');
  });

  test('Gemini key configuration and connection test reuse the registered Gemini adapter without prompt POST', () async {
    await manager.initialize();
    await manager.saveGeminiApiKey('user_gemini_key');
    expect(manager.statusFor('gemini'), ManagedProviderStatus.disconnected);
    expect(geminiTransport.getRequests, 0);
    await manager.testConnection('gemini');
    expect(manager.statusFor('gemini'), ManagedProviderStatus.connected);
    expect(geminiTransport.getRequests, 1);
    expect(geminiTransport.postRequests, 0);
  });

  test('Gemini connection failure remains Disconnected and emits a safe error without prompt traffic', () async {
    await manager.initialize();
    await manager.saveGeminiApiKey('user_gemini_key');
    geminiTransport.getResponse = const AiHttpResponse(403, []);
    await expectLater(manager.testConnection('gemini'), throwsA(isA<MarketProviderException>()));
    expect(manager.statusFor('gemini'), ManagedProviderStatus.error);
    expect(manager.messageFor('gemini'), isNot(contains('user_gemini_key')));
    expect(geminiTransport.getRequests, 1);
    expect(geminiTransport.postRequests, 0);
  });

  test('disconnect deletes only the selected credential and explicit Cloudflare metadata', () async {
    await manager.initialize();
    await manager.saveCloudflareConfiguration(token: 'cloudflare-user-token-secret', accountId: 'aabbccddeeff00112233445566778899');
    await manager.saveGeminiApiKey('user_gemini_key');
    await credentials.save(providerId: 'cloudflare_workers', kind: SecureCredentialKind.accessToken, secret: 'legacy-worker-token');
    await manager.disconnect('cloudflare');
    expect(manager.cloudflareConfigured, isFalse);
    expect(manager.statusFor('cloudflare'), ManagedProviderStatus.installed);
    expect(await credentials.read(providerId: 'cloudflare', kind: SecureCredentialKind.accessToken), isNull);
    expect(manager.cloudflareAccountId, isNull);
    expect(await credentials.read(providerId: 'gemini', kind: SecureCredentialKind.apiKey), 'user_gemini_key');
    expect(await credentials.read(providerId: 'cloudflare_workers', kind: SecureCredentialKind.accessToken), 'legacy-worker-token');
    expect(manager.geminiConfigured, isTrue);
  });

  test('Local AI source and source archive digest are pinned to official llama.cpp', () {
    expect(MarketProviderManager.localAiRuntimeCommit, 'ea722948146befb23c9529c1ec7f59fb2f34911f');
    expect(MarketProviderManager.localAiRuntimeSource.toString(),
        'https://github.com/ggml-org/llama.cpp/tree/ea722948146befb23c9529c1ec7f59fb2f34911f');
    expect(MarketProviderManager.localAiBuildDocs.toString(), contains('/docs/android.md'));
    expect(MarketProviderManager.localAiLicenseDocs.toString(), endsWith('/LICENSE'));
    expect(MarketProviderManager.localAiSourceArchiveSha256, '05b362e97564f2e449440f13878c43991a13b6029214dbcb0d1b116b20365ec2');
    expect(MarketProviderManager.localAiModelsDocs.toString(), 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/blob/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf');
  });

  test('Local AI remains Not Ready and never invokes cloud or a fake inference', () async {
    await manager.initialize();
    await expectLater(manager.testInference(), throwsA(isA<MarketProviderException>()));
    expect(manager.statusFor('local_ai'), ManagedProviderStatus.notReady);
    expect(manager.messageFor('local_ai'), isNull);
    expect(cloudflare.requests, 0);
    expect(geminiTransport.postRequests, 0);
  });

  test('capability parsing rejects incomplete or invalid native telemetry', () {
    expect(LocalAiDeviceCapabilities.tryParse({'supportedAbis': [], 'totalRamBytes': -1}), isNull);
    final capabilities = LocalAiDeviceCapabilities.tryParse({
      'supportedAbis': ['arm64-v8a'],
      'totalRamBytes': 8 * 1024 * 1024 * 1024,
      'availableRamBytes': 4 * 1024 * 1024 * 1024,
      'totalStorageBytes': 128 * 1024 * 1024 * 1024,
      'availableStorageBytes': 32 * 1024 * 1024 * 1024,
      'runtimeAvailable': false,
      'installedModelCount': 0,
    });
    expect(capabilities!.supportedAbis, ['arm64-v8a']);
    expect(capabilities.runtimeAvailable, isFalse);
    expect(capabilities.installedModelCount, 0);
  });

  test('provider registry exposes Cloudflare least-privilege category and keeps Local AI separate', () {
    final cloudflareProvider = providerRegistry.singleWhere((provider) => provider.id == 'cloudflare');
    final localProvider = providerRegistry.singleWhere((provider) => provider.id == 'local_ai');
    expect(cloudflareProvider.category, ProviderCategory.cloudInfrastructure);
    expect(cloudflareProvider.authType, ProviderAuthType.scopedToken);
    expect(cloudflareProvider.setupGuidance, contains('does not manage Workers, DNS'));
    expect(localProvider.category, ProviderCategory.onDeviceAi);
  });
}
