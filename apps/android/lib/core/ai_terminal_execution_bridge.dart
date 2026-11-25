import 'dart:io';

import 'policy_engine.dart';
import 'terminal_process_executor.dart';
import 'terminal_runtime_adapter.dart';
import 'terminal_session_manager.dart';

/// A strictly typed proposal a future connected AI provider may submit.
/// Raw shell text, arbitrary arguments, and unregistered tool IDs are rejected.
class AiTerminalToolProposal {
  const AiTerminalToolProposal._({required this.toolId, required this.target, required this.rationale});

  static const supportedToolIds = terminalSupportedToolIds;

  static bool _isEligibleAiTarget(String host) {
    final normalized = host.toLowerCase();
    if (!normalized.contains('.') || PolicyEngine.isRestrictedHostname(normalized)) return false;
    if (const ['.example', '.test', '.invalid', '.home.arpa', '.lan', '.corp', '.intranet'].any((suffix) => normalized.endsWith(suffix))) return false;
    final address = InternetAddress.tryParse(normalized);
    return address == null || (!PolicyEngine.isRestrictedAddress(address) && !PolicyEngine.isCloudMetadataAddress(address));
  }

  final String toolId;
  final String target;
  final String rationale;

  static AiTerminalToolProposal? parseToolCall({required String name, required Map<String, Object?> arguments}) {
    if (name != 'run_security_tool' ||
        arguments.keys.any((key) => !const {'tool_id', 'target', 'rationale'}.contains(key)) ||
        !arguments.containsKey('tool_id') ||
        !arguments.containsKey('target')) {
      return null;
    }
    final toolId = arguments['tool_id'];
    final target = arguments['target'];
    final rationale = arguments['rationale'] ?? '';
    if (toolId is! String ||
        !supportedToolIds.contains(toolId) ||
        target is! String ||
        !isSafeTerminalHostTarget(target) ||
        !_isEligibleAiTarget(target) ||
        rationale is! String ||
        rationale.trim().isEmpty ||
        rationale.length > 400 ||
        rationale.codeUnits.any((unit) => unit < 0x20 && unit != 0x09)) {
      return null;
    }
    return AiTerminalToolProposal._(
      toolId: toolId,
      target: target,
      rationale: rationale.trim(),
    );
  }
}

/// The single typed AI-to-tool gate. A proposal must be registered, ready,
/// explicitly reviewed by the user, and then pass the existing consent-gated
/// terminal/runtime adapter. It never accepts or executes shell commands.
class AiTerminalExecutionBridge {
  const AiTerminalExecutionBridge({required this.runtime});

  final TerminalToolRuntime runtime;

  Future<TerminalExecutionResult> executeProposal(
    AiTerminalToolProposal proposal, {
    required Future<bool> Function(AiTerminalToolProposal proposal) reviewWithUser,
    required String Function(String source) translate,
    String? requestId,
  }) async {
    try {
      final readyTools = await runtime.readyToolIds();
      if (!readyTools.contains(proposal.toolId)) {
        return TerminalExecutionResult.failed(translate('The AI-requested tool is not currently ready.'));
      }
      final approved = await reviewWithUser(proposal);
      if (!approved) return TerminalExecutionResult.cancelled(translate('AI tool request declined; no tool was run.'));
      return await runtime.executeTool(
        proposal.toolId,
        proposal.target,
        translate: translate,
        correlationId: requestId,
      );
    } catch (_) {
      return TerminalExecutionResult.failed(translate('The AI tool request could not be completed.'));
    }
  }
}
