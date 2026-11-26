import 'dart:convert';
import 'dart:io';

import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:cybersecurity_assistant/core/ai_assistant_coordinator.dart';
import 'package:cybersecurity_assistant/core/ai_data_sharing_consent.dart';
import 'package:cybersecurity_assistant/core/ai_provider_manager.dart';
import 'package:cybersecurity_assistant/core/ai_terminal_execution_bridge.dart';
import 'package:cybersecurity_assistant/core/market_provider_manager.dart';
import 'package:cybersecurity_assistant/core/local_ai_inference_runtime.dart';
import 'package:cybersecurity_assistant/core/local_ai_model_manifest.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:cybersecurity_assistant/core/terminal_runtime_adapter.dart';
import 'package:cybersecurity_assistant/core/tool_orchestrator.dart';
import 'package:cybersecurity_assistant/l10n/app_localizations.dart';
import 'package:cybersecurity_assistant/widgets/assistant_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;

class _MemorySecureBackend implements SecureStorageBackend {
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

class _FakeAiTransport implements AiHttpTransport {
  int postCount = 0;

  @override
  Future<AiHttpResponse> get(Uri uri, Map<String, String> headers) async => AiHttpResponse(
        200,
        utf8.encode(jsonEncode({'name': 'models/${GeminiAiProviderAdapter.modelId}'})),
      );

  @override
  Future<AiHttpResponse> post(Uri uri, Map<String, String> headers, List<int> body) async {
    postCount++;
    return AiHttpResponse(200, utf8.encode(jsonEncode({
      'candidates': [
        {'content': {'parts': [{'text': 'Fake Gemini reply'}]}},
      ],
    })));
  }
}

Future<void> _pumpAssistantFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('Assistant asks once per provider, persists consent, and asks again after revocation', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const capabilityChannel = MethodChannel('org.cybersecurityassistant/local_ai_capabilities');
    const localRuntimeChannel = MethodChannel('test/assistant_local_ai_runtime');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(capabilityChannel, (call) async => null);
    messenger.setMockMethodCallHandler(localRuntimeChannel, (call) async => {
      'sourceCommit': AndroidLlamaCppInferenceRuntime.sourceCommit,
      'runtimeLoaded': true,
      'modelLoaded': true,
      'modelName': LocalAiModelManifest.qwenQ4Km.fileName,
      'modelSha256': LocalAiModelManifest.qwenQ4Km.sha256Hex,
      'publisherMetadataVerified': true,
      'inferenceSucceeded': true,
      'offlineInferenceSucceeded': false,
      'abi': 'arm64-v8a',
      'backend': 'cpu',
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(capabilityChannel, null);
      messenger.setMockMethodCallHandler(localRuntimeChannel, null);
    });

    final backend = _MemorySecureBackend();
    final credentials = SecureCredentialStore(backend: backend);
    await credentials.save(providerId: 'gemini', kind: SecureCredentialKind.apiKey, secret: 'AIzaSyExample_Key-0123456789');
    final transport = _FakeAiTransport();
    final providers = AiProviderManager(
      credentialStore: credentials,
      adapters: [
        GeminiAiProviderAdapter(credentialStore: credentials, transport: transport),
        const LocalAiProviderAdapter(AndroidLlamaCppInferenceRuntime(channel: localRuntimeChannel)),
      ],
    );
    final marketProviders = MarketProviderManager(
      credentials: credentials,
      configuration: ProviderConfigurationStore(backend),
      aiProviders: providers,
    );
    await marketProviders.initialize();
    stderr.writeln('CONSENT_TEST_STAGE manager-initialized');
    final consentStore = AiDataSharingConsentStore(backend: backend);
    final activityStore = MemoryActivityHistoryStore();
    final coordinator = AiAssistantCoordinator(
      providers: providers,
      bridge: AiTerminalExecutionBridge(runtime: TerminalRuntimeAdapter(
        orchestrator: ToolOrchestrator(),
        runAfterConsent: (String toolId, String? target, {String? correlationId}) async => null,
      )),
      activityStore: activityStore,
    );

    addTearDown(() {
      marketProviders.dispose();
      providers.close();
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
      home: AssistantScreen(
        providers: providers,
        marketProviders: marketProviders,
        consentStore: consentStore,
        coordinator: coordinator,
        reviewTool: (_) async => false,
        onOpenMarket: () async {},
        onOpenTools: () {},
      ),
    ));
    await _pumpAssistantFrame(tester);
    stderr.writeln('CONSENT_TEST_STAGE assistant-rendered');

    expect(find.byKey(const ValueKey('assistant-floating-composer')), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await _pumpAssistantFrame(tester);
    const localProviderLabel = 'Local AI (offline test needed)';
    expect(find.text(localProviderLabel), findsOneWidget,
        reason: 'The verified model must be selectable for a first Chat attempt without being labelled Ready.');
    await tester.tap(find.text(localProviderLabel));
    await _pumpAssistantFrame(tester);
    expect(find.text('Local Chat is available, but readiness stays Not Ready until a real response succeeds with airplane mode on and no internet network.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await _pumpAssistantFrame(tester);
    await tester.tap(find.text('Google Gemini'));
    await _pumpAssistantFrame(tester);
    expect(find.byIcon(Icons.check_rounded), findsNothing,
        reason: 'A saved Gemini key alone must not show the green connection check.');
    expect(find.byKey(const ValueKey('assistant-info-button')), findsOneWidget);
    expect(find.text('Example questions'), findsOneWidget);
    expect(find.text('Consent required before first message to this provider'), findsOneWidget);
    await tester.tap(find.text('Explain what this security finding means'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Explain what this security finding means');
    await tester.tap(find.byKey(const ValueKey('assistant-info-button')));
    await _pumpAssistantFrame(tester);
    expect(find.text('Privacy and consent'), findsOneWidget);
    expect(find.text('Separate tool approval'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await _pumpAssistantFrame(tester);
    await marketProviders.testConnection('gemini');
    stderr.writeln('CONSENT_TEST_STAGE provider-checked');
    await _pumpAssistantFrame(tester);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget,
        reason: 'The green connection check appears only after the provider test succeeds.');
    await tester.enterText(find.byType(TextField), 'Explain DNS safely');
    await tester.tap(find.byTooltip('Send'));
    await _pumpAssistantFrame(tester);

    expect(find.text('AI data-sharing consent'), findsOneWidget);
    stderr.writeln('CONSENT_TEST_STAGE consent-dialog-open');
    final continueButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(continueButton.onPressed, isNull, reason: 'The agreement checkbox must be checked before continuing.');
    await tester.tap(find.byKey(const ValueKey('ai-data-sharing-consent-checkbox')));
    await _pumpAssistantFrame(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await _pumpAssistantFrame(tester);
    stderr.writeln('CONSENT_TEST_STAGE first-consent-accepted');

    expect(await consentStore.hasConsent('gemini'), isTrue);
    expect(transport.postCount, 1);
    expect(find.text('Fake Gemini reply'), findsOneWidget);
    stderr.writeln('CONSENT_TEST_STAGE first-response-rendered');

    await tester.enterText(find.byType(TextField), 'What is a DNS record?');
    await tester.tap(find.byTooltip('Send'));
    await _pumpAssistantFrame(tester);
    expect(find.text('AI data-sharing consent'), findsNothing,
        reason: 'The saved provider-specific consent prevents repeated confirmation.');
    expect(transport.postCount, 2);
    stderr.writeln('CONSENT_TEST_STAGE second-response-rendered');

    await consentStore.revoke('gemini');
    await tester.enterText(find.byType(TextField), 'Check this again');
    await tester.tap(find.byTooltip('Send'));
    await _pumpAssistantFrame(tester);
    expect(find.text('AI data-sharing consent'), findsOneWidget,
        reason: 'Revoking consent requires a fresh decision before the next send.');
    expect(transport.postCount, 2, reason: 'No network request is made before renewed consent.');
  });
}
