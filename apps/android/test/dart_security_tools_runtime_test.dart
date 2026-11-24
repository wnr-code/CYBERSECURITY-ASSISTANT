import 'dart:convert';
import 'dart:io';

import 'package:cybersecurity_assistant/core/dart_security_tools_runtime.dart';
import 'package:cybersecurity_assistant/core/runtime_manager.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/tool_result_codec.dart';
import 'package:flutter_test/flutter_test.dart';

class _AdapterTools extends SecurityTools {
  int dnsCalls = 0;

  @override
  Future<ToolRunResult> runDnsLookup(String input, {required bool authorized, ToolCancellation? cancellationToken}) async {
    dnsCalls++;
    return ToolRunResult(
      toolId: 'dns_lookup',
      target: input,
      summary: 'Fixture DNS result',
      details: const ['A record: 192.0.2.8'],
      findings: const [],
      completedAt: DateTime.utc(2026, 11, 23),
      authorizationConfirmed: authorized,
    );
  }
}

void main() {
  late Directory workspace;
  late _AdapterTools tools;
  late DartSecurityToolsRuntime adapter;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('bundled-dart-runtime-');
    tools = _AdapterTools();
    adapter = DartSecurityToolsRuntime(tools: tools);
    await adapter.install(workspace);
    await adapter.initialize(workspace);
  });

  tearDown(() async {
    await adapter.stop();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  test('only dispatches statically allowlisted tools with exact input fields', () async {
    final result = await adapter.executeTool(RuntimeToolRequest(
      toolId: 'dns_lookup',
      input: const {'target': 'owned.example'},
      requiredCapabilities: const {RuntimeCapability.network},
      networkAuthorized: true,
      cancellationToken: RuntimeCancellationToken(),
    ));
    final decoded = decodeToolRunResult(jsonEncode(result));
    expect(decoded.toolId, 'dns_lookup');
    expect(decoded.target, 'owned.example');
    expect(tools.dnsCalls, 1);

    await expectLater(
      adapter.executeTool(RuntimeToolRequest(
        toolId: 'sh', input: const {'target': 'owned.example'},
        requiredCapabilities: const {}, networkAuthorized: true, cancellationToken: RuntimeCancellationToken(),
      )),
      throwsA(isA<RuntimeExecutionException>()),
    );
    await expectLater(
      adapter.executeTool(RuntimeToolRequest(
        toolId: 'dns_lookup', input: const {'target': 'owned.example', 'command': 'id'},
        requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: true, cancellationToken: RuntimeCancellationToken(),
      )),
      throwsFormatException,
    );
  });

  test('validates installed manifest and health state', () async {
    expect(await adapter.healthCheck(), isTrue);
    await File('${workspace.path}/runtime-manifest.json').writeAsString('{"runtimeId":"tampered"}');
    expect(await adapter.healthCheck(), isFalse);
    await expectLater(adapter.initialize(workspace), throwsFormatException);
  });

  test('local response analysis refuses network capability requests', () async {
    final prior = ToolRunResult(
      toolId: 'dns_lookup', target: 'owned.example', summary: 'DNS result', details: const ['A record'],
      findings: const [], completedAt: DateTime.utc(2026, 11, 23),
    );
    final request = RuntimeToolRequest(
      toolId: 'response_analyzer',
      input: {'target': 'owned.example', 'priorResults': [encodeToolRunResult(prior)]},
      requiredCapabilities: const {},
      networkAuthorized: false,
      cancellationToken: RuntimeCancellationToken(),
    );
    final output = await adapter.executeTool(request);
    expect(decodeToolRunResult(jsonEncode(output)).toolId, 'response_analyzer');

    await expectLater(
      adapter.executeTool(RuntimeToolRequest(
        toolId: 'response_analyzer', input: {'target': 'owned.example', 'priorResults': [encodeToolRunResult(prior)]},
        requiredCapabilities: const {RuntimeCapability.network}, networkAuthorized: false,
        cancellationToken: RuntimeCancellationToken(),
      )),
      throwsA(isA<RuntimeExecutionException>()),
    );
  });
}
