import 'tool_orchestrator.dart';
import 'tool_registry.dart';
import 'terminal_session_manager.dart';

const terminalSupportedToolIds = {'dns_lookup', 'tls_inspector', 'http_headers'};

abstract interface class TerminalToolRuntime {
  Future<List<String>> readyToolIds();
  Future<TerminalExecutionResult> executeTool(
    String toolId,
    String? target, {
    required String Function(String source) translate,
    String? correlationId,
  });
}

/// Bridges terminal requests to the reviewed tool catalog and Runtime Manager.
/// Execution is delegated to the existing, consent-gated tool runner UI.
class TerminalRuntimeAdapter implements TerminalToolRuntime {
  TerminalRuntimeAdapter({required this.orchestrator, required this.runAfterConsent});

  final ToolOrchestrator orchestrator;
  final Future<TerminalExecutionResult?> Function(String toolId, String? target, {String? correlationId}) runAfterConsent;

  @override
  Future<List<String>> readyToolIds() async {
    final available = <String>[];
    for (final definition in orchestrator.registry.definitions) {
      if (!terminalSupportedToolIds.contains(definition.id) || !definition.enabled) continue;
      try {
        final status = await orchestrator.statusForTool(definition.id);
        if (status == ToolStatus.ready) available.add(definition.id);
      } catch (_) {
        // An unknown/unavailable runtime is not exposed as a runnable shortcut.
      }
    }
    return List.unmodifiable(available);
  }

  @override
  Future<TerminalExecutionResult> executeTool(
    String toolId,
    String? target, {
    required String Function(String source) translate,
    String? correlationId,
  }) async {
    if (!terminalSupportedToolIds.contains(toolId)) {
      return TerminalExecutionResult.failed(translate('This terminal tool is not allowlisted.'));
    }
    final definition = orchestrator.registry.byId(toolId);
    if (definition == null || !definition.enabled) {
      return TerminalExecutionResult.failed(translate('This tool is not registered in the app.'));
    }
    try {
      final availability = await orchestrator.availabilityForTool(toolId);
      if (!availability.ready) {
        return TerminalExecutionResult.failed(translate('This tool is not ready in the Runtime Manager.'));
      }
      final result = await runAfterConsent(toolId, target, correlationId: correlationId);
      if (result == null) return TerminalExecutionResult.cancelled(translate('The check was cancelled; no tool was run.'));
      return result;
    } catch (_) {
      return TerminalExecutionResult.failed(translate('The tool did not complete. Review Reports or the Activity Timeline.'));
    }
  }
}
