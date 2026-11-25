import 'dart:convert';

import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:cybersecurity_assistant/core/ai_assistant_coordinator.dart';
import 'package:cybersecurity_assistant/core/ai_provider_manager.dart';
import 'package:cybersecurity_assistant/core/ai_terminal_execution_bridge.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:cybersecurity_assistant/core/terminal_runtime_adapter.dart';
import 'package:cybersecurity_assistant/core/terminal_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _FakeTransport implements AiHttpTransport {
  _FakeTransport(this.response);
  final AiHttpResponse response;
  Uri? uri;
  Map<String, String>? headers;
  Map<String, dynamic>? payload;
  AiHttpResponse? getResponse;
  int getRequests = 0;
  @override
  Future<AiHttpResponse> get(Uri uri, Map<String, String> headers) async {
    this.uri = uri;
    this.headers = headers;
    getRequests++;
    return getResponse ?? response;
  }
  @override
  Future<AiHttpResponse> post(Uri uri, Map<String, String> headers, List<int> body) async {
    this.uri = uri;
    this.headers = headers;
    payload = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    return response;
  }
}

class _SequenceProvider implements AiProviderAdapter {
  _SequenceProvider(this.replies);
  final List<AiProviderReply> replies;
  final requests = <List<AiChatMessage>>[];
  @override
  String get providerId => 'local_ai';
  @override
  Future<AiProviderReply> complete(List<AiChatMessage> messages) async {
    requests.add(List.of(messages));
    return replies.removeAt(0);
  }
}

class _FakeLocalInference implements LocalAiInferenceRuntime {
  @override
  Future<AiProviderReply> complete(List<AiChatMessage> messages) async => const AiProviderReply(text: 'local response');
}

class _FakeToolRuntime implements TerminalToolRuntime {
  String? correlation;
  @override
  Future<List<String>> readyToolIds() async => const ['dns_lookup'];
  @override
  Future<TerminalExecutionResult> executeTool(String toolId, String? target, {
    required String Function(String source) translate,
    String? correlationId,
  }) async {
    correlation = correlationId;
    return const TerminalExecutionResult.completed(
      'Resolved 2 addresses.',
      executionId: 'runtime-exec-actual-42',
      executionData: const {'tool_id': 'dns_lookup', 'summary': 'Resolved 2 addresses.'},
    );
  }
}

void main() {
  test('Gemini adapter uses fixed HTTPS endpoint and parses text and registered function calls', () async {
    final memory = _MemorySecureStore();
    final credentials = SecureCredentialStore(backend: memory);
    await credentials.save(providerId: 'gemini', kind: SecureCredentialKind.apiKey, secret: 'user-owned-secret');
    final transport = _FakeTransport(AiHttpResponse(200, utf8.encode(jsonEncode({
      'candidates': [
        {'content': {'parts': [
          {'text': 'I can check the authorized host.'},
          {'functionCall': {'name': 'run_security_tool', 'args': {
            'tool_id': 'dns_lookup', 'target': 'example.org', 'rationale': 'Review its public DNS records.'
          }}},
        ]}},
      ],
    }))));
    final adapter = GeminiAiProviderAdapter(credentialStore: credentials, transport: transport);
    final result = await adapter.complete([AiChatMessage.user('Check example.org')]);

    expect(transport.uri!.scheme, 'https');
    expect(transport.uri!.host, 'generativelanguage.googleapis.com');
    expect(transport.uri!.query, isEmpty);
    expect(transport.headers!['x-goog-api-key'], 'user-owned-secret');
    expect(result.text, 'I can check the authorized host.');
    expect(result.toolCalls.single.name, 'run_security_tool');
    expect(result.toolCalls.single.arguments['tool_id'], 'dns_lookup');
    expect(transport.payload!['tools'], isNotEmpty);
  });

  test('Gemini Test Connection checks configured model metadata without submitting a prompt', () async {
    final memory = _MemorySecureStore();
    final credentials = SecureCredentialStore(backend: memory);
    await credentials.save(providerId: 'gemini', kind: SecureCredentialKind.apiKey, secret: 'user-owned-secret');
    final transport = _FakeTransport(const AiHttpResponse(200, []))
      ..getResponse = AiHttpResponse(200, utf8.encode(jsonEncode({'name': 'models/gemini-3.5-flash-lite'})));
    final adapter = GeminiAiProviderAdapter(credentialStore: credentials, transport: transport);

    await adapter.testConnection();

    expect(transport.getRequests, 1);
    expect(transport.uri!.path, '/v1beta/models/gemini-3.5-flash-lite');
    expect(transport.uri!.query, isEmpty);
    expect(transport.headers!['x-goog-api-key'], 'user-owned-secret');
    expect(transport.payload, isNull);
  });

  test('bounded coordinator sends actual execution receipt back to model and correlates audit records', () async {
    final provider = _SequenceProvider([
      const AiProviderReply(text: '', toolCalls: [AiToolCall(name: 'run_security_tool', arguments: {
        'tool_id': 'dns_lookup', 'target': 'example.org', 'rationale': 'Check public DNS records.'
      })]),
      const AiProviderReply(text: 'The runtime resolved two addresses.'),
    ]);
    final credentials = SecureCredentialStore(backend: _MemorySecureStore());
    final manager = AiProviderManager(credentialStore: credentials, adapters: [provider]);
    final runtime = _FakeToolRuntime();
    final activityStore = MemoryActivityHistoryStore();
    final coordinator = AiAssistantCoordinator(
      providers: manager,
      bridge: AiTerminalExecutionBridge(runtime: runtime),
      activityStore: activityStore,
    );
    final result = await coordinator.submit(
      providerId: 'local_ai',
      prompt: 'Review example.org',
      reviewTool: (_) async => true,
      translate: (source) => source,
    );

    expect(result.reply, 'The runtime resolved two addresses.');
    expect(result.toolExecutions.single.executionId, 'runtime-exec-actual-42');
    expect(runtime.correlation, result.requestId);
    expect(provider.requests, hasLength(2));
    final toolResponse = provider.requests.last.last;
    expect(toolResponse.role, 'tool');
    expect(toolResponse.toolResponse!['execution_id'], 'runtime-exec-actual-42');
    expect(toolResponse.toolResponse!['stdout'], isNull);
    expect(toolResponse.toolResponse!['stderr'], isNull);
    expect(toolResponse.toolResponse!['exit_code'], isNull);
    final audit = await activityStore.loadActivityById(result.requestId);
    expect(audit!.kind, ActivityKind.aiRequest);
    expect(audit.status, ActivityStatus.completed);
    expect(audit.target, 'local_ai');
  });

  test('Local AI adapter delegates only to the supplied on-device inference runtime', () async {
    final adapter = LocalAiProviderAdapter(_FakeLocalInference());
    expect(adapter.providerId, 'local_ai');
    expect((await adapter.complete([AiChatMessage.user('local only')])).text, 'local response');
  });

  test('Gemini readiness is false without a stored user key', () async {
    final credentials = SecureCredentialStore(backend: _MemorySecureStore());
    final manager = AiProviderManager(
      credentialStore: credentials,
      adapters: [GeminiAiProviderAdapter(credentialStore: credentials, transport: _FakeTransport(const AiHttpResponse(200, [])))],
    );
    expect(await manager.isReady('gemini'), isFalse);
  });
}
