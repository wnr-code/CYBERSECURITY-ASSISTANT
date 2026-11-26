import 'dart:math';

import 'activity_timeline.dart';
import 'ai_provider_manager.dart';
import 'ai_terminal_execution_bridge.dart';
import 'terminal_session_manager.dart';

class AiAssistantTurnResult {
  const AiAssistantTurnResult({required this.requestId, required this.reply, required this.toolExecutions});
  final String requestId;
  final String reply;
  final List<TerminalExecutionResult> toolExecutions;
}

/// Bounded multi-step orchestration. Every proposed tool is independently
/// validated and sent through the existing user-consent/runtime path.
class AiAssistantCoordinator {
  AiAssistantCoordinator({required this.providers, required this.bridge, required this.activityStore});
  final AiProviderManager providers;
  final AiTerminalExecutionBridge bridge;
  final ActivityHistoryStore activityStore;
  static const maxModelTurns = 5;
  static const maxToolCalls = 4;
  static const maxPromptLength = 4000;
  static final Random _random = Random.secure();

  Future<AiAssistantTurnResult> submit({
    required String providerId,
    required String prompt,
    required Future<bool> Function(AiTerminalToolProposal proposal) reviewTool,
    required String Function(String source) translate,
  }) async {
    final userText = prompt.trim();
    if (userText.isEmpty || userText.length > maxPromptLength) {
      throw const AiProviderException('Enter a message within the allowed size.');
    }
    final requestId = _newRequestId();
    final startedAt = DateTime.now().toUtc();
    final event = ActivityEvent(
      eventId: requestId,
      kind: ActivityKind.aiRequest,
      target: providerId,
      status: ActivityStatus.started,
      startedAt: startedAt,
      summary: 'Assistant request started.',
    ).validated();
    // Fail closed: no prompt or tool execution is sent without a durable local
    // request anchor to which runtime activities can be linked.
    await activityStore.upsertActivity(event);
    try {
      final result = await _runRequest(
        requestId: requestId,
        providerId: providerId,
        prompt: userText,
        reviewTool: reviewTool,
        translate: translate,
      );
      await activityStore.upsertActivity(event.copyWith(
        status: ActivityStatus.completed,
        finishedAt: DateTime.now().toUtc(),
        summary: 'Assistant request completed.',
      ));
      return result;
    } catch (_) {
      try {
        await activityStore.upsertActivity(event.copyWith(
          status: ActivityStatus.failed,
          finishedAt: DateTime.now().toUtc(),
          summary: 'Assistant request failed; prompt content was not recorded.',
        ));
      } catch (_) {
        // Preserve the original provider/runtime failure; never log prompt text.
      }
      rethrow;
    }
  }

  Future<AiAssistantTurnResult> _runRequest({
    required String requestId,
    required String providerId,
    required String prompt,
    required Future<bool> Function(AiTerminalToolProposal proposal) reviewTool,
    required String Function(String source) translate,
  }) async {
    final history = <AiChatMessage>[AiChatMessage.user(prompt)];
    final executions = <TerminalExecutionResult>[];
    var callCount = 0;
    for (var turn = 0; turn < maxModelTurns; turn++) {
      final reply = await providers.complete(providerId, history);
      final calls = reply.toolCalls;
      if (calls.isEmpty) {
        return AiAssistantTurnResult(
          requestId: requestId,
          reply: reply.text.trim().isEmpty ? translate('The AI provider returned an empty response.') : reply.text.trim(),
          toolExecutions: List.unmodifiable(executions),
        );
      }
      history.add(AiChatMessage.assistant(reply.text, toolCalls: calls));
      for (final call in calls) {
        if (++callCount > maxToolCalls) {
          return AiAssistantTurnResult(
            requestId: requestId,
            reply: translate('The assistant reached the safe limit for tool steps in this request.'),
            toolExecutions: List.unmodifiable(executions),
          );
        }
        final proposal = AiTerminalToolProposal.parseToolCall(name: call.name, arguments: call.arguments);
        if (proposal == null) {
          history.add(AiChatMessage.toolResponse(aiFunctionName, {
            'status': 'rejected',
            'message': 'Invalid or unsupported tool proposal; no tool was executed.',
          }));
          continue;
        }
        final execution = await bridge.executeProposal(
          proposal,
          requestId: requestId,
          reviewWithUser: reviewTool,
          translate: translate,
        );
        executions.add(execution);
        final response = <String, Object?>{
          'status': execution.cancelled ? 'cancelled' : execution.succeeded ? 'completed' : 'failed',
          'execution_id': execution.executionId,
          'result': execution.executionData,
          'message': _boundedProviderResult(execution.output),
          // These built-in app-owned tools are structured runtime operations,
          // not child processes. No synthetic process streams or exit codes.
          'stdout': null,
          'stderr': null,
          'exit_code': null,
        };
        history.add(AiChatMessage.toolResponse(aiFunctionName, response));
      }
    }
    return AiAssistantTurnResult(
      requestId: requestId,
      reply: translate('The assistant reached the safe limit for tool steps in this request.'),
      toolExecutions: List.unmodifiable(executions),
    );
  }

  static String _newRequestId() => 'ai-${DateTime.now().toUtc().microsecondsSinceEpoch}-${_random.nextInt(1 << 32).toRadixString(16)}';

  static String _boundedProviderResult(String text) {
    const maxChars = 8000;
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)} [truncated]';
  }
}
