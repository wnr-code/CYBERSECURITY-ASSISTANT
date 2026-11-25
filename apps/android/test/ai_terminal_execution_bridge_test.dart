import 'package:cybersecurity_assistant/core/ai_terminal_execution_bridge.dart';
import 'package:cybersecurity_assistant/core/terminal_runtime_adapter.dart';
import 'package:cybersecurity_assistant/core/terminal_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTerminalRuntime implements TerminalToolRuntime {
  List<String> ready = const ['dns_lookup'];
  final calls = <String>[];

  @override
  Future<List<String>> readyToolIds() async => ready;

  @override
  Future<TerminalExecutionResult> executeTool(
    String toolId,
    String? target, {
    required String Function(String source) translate,
    String? correlationId,
  }) async {
    calls.add('$toolId:$target');
    return TerminalExecutionResult.completed('execution accepted', executionId: 'test-runtime-execution');
  }
}

void main() {
  test('model tool-call parser accepts typed registered-tool proposals only', () {
    final proposal = AiTerminalToolProposal.parseToolCall(
      name: 'run_security_tool',
      arguments: const {'tool_id': 'dns_lookup', 'target': 'owned.example.com', 'rationale': 'Resolve the authorized host.'},
    );
    expect(proposal?.toolId, 'dns_lookup');
    expect(proposal?.target, 'owned.example.com');
    expect(proposal?.rationale, 'Resolve the authorized host.');

    expect(
      AiTerminalToolProposal.parseToolCall(
        name: 'execute_shell',
        arguments: const {'command': 'id'},
      ),
      isNull,
    );
    expect(
      AiTerminalToolProposal.parseToolCall(
        name: 'workspace_read',
        arguments: const {'path': 'src/main.dart'},
      ),
      isNull,
      reason: 'AI provider proposals must not expose the workspace filesystem.',
    );
    expect(
      AiTerminalToolProposal.parseToolCall(
        name: 'run_security_tool',
        arguments: const {'tool_id': 'workspace_read', 'target': 'src/main.dart'},
      ),
      isNull,
      reason: 'AI provider proposals must not expose the workspace filesystem.',
    );
    expect(
      AiTerminalToolProposal.parseToolCall(
        name: 'run_security_tool',
        arguments: const {'tool_id': 'dns_lookup;rm', 'target': 'owned.example.com'},
      ),
      isNull,
    );
    expect(
      AiTerminalToolProposal.parseToolCall(
        name: 'run_security_tool',
        arguments: const {'tool_id': 'dns_lookup', 'target': 'https://owned.example.com/path'},
      ),
      isNull,
    );
    for (final internalHost in ['localhost', 'router.local', 'metadata.google.internal', 'service.internal', '192.168.1.1']) {
      expect(
        AiTerminalToolProposal.parseToolCall(
          name: 'run_security_tool',
          arguments: {'tool_id': 'dns_lookup', 'target': internalHost},
        ),
        isNull,
        reason: 'AI proposals must reject local/internal targets: $internalHost',
      );
    }
    expect(
      AiTerminalToolProposal.parseToolCall(
        name: 'run_security_tool',
        arguments: const {'tool_id': 'dns_lookup', 'target': 'owned.example.com', 'command': 'rm -rf'},
      ),
      isNull,
    );
  });

  test('bridge requires readiness and explicit human review before tool execution', () async {
    final runtime = _FakeTerminalRuntime();
    final bridge = AiTerminalExecutionBridge(runtime: runtime);
    final proposal = AiTerminalToolProposal.parseToolCall(
      name: 'run_security_tool',
      arguments: const {'tool_id': 'dns_lookup', 'target': 'owned.example.com', 'rationale': 'Review DNS records.'},
    )!;
    var reviewed = false;

    runtime.ready = const [];
    final unavailable = await bridge.executeProposal(
      proposal,
      reviewWithUser: (_) async {
        reviewed = true;
        return true;
      },
      translate: (source) => source,
    );
    expect(unavailable.succeeded, isFalse);
    expect(reviewed, isFalse);
    expect(runtime.calls, isEmpty);

    runtime.ready = const ['dns_lookup'];
    final declined = await bridge.executeProposal(
      proposal,
      reviewWithUser: (candidate) async {
        reviewed = candidate.rationale == 'Review DNS records.';
        return false;
      },
      translate: (source) => source,
    );
    expect(declined.cancelled, isTrue);
    expect(reviewed, isTrue);
    expect(runtime.calls, isEmpty);

    final accepted = await bridge.executeProposal(
      proposal,
      reviewWithUser: (_) async => true,
      translate: (source) => source,
    );
    expect(accepted.succeeded, isTrue);
    expect(runtime.calls, ['dns_lookup:owned.example.com']);
  });
}
