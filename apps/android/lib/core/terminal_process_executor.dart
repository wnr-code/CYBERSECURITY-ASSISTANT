import 'terminal_runtime_adapter.dart';
import 'terminal_session_manager.dart';
import 'workspace_file_system.dart';

final RegExp _terminalHostName = RegExp(
  r'^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$',
);

bool isSafeTerminalHostTarget(String value) => value.length <= 253 && _terminalHostName.hasMatch(value);

/// Executes a deliberately small app-owned command set. It never invokes
/// Process.start, a shell, a script interpreter, or an arbitrary executable.
class SafeTerminalProcessExecutor {
  const SafeTerminalProcessExecutor({required this.runtimeAdapter, this.workspaceProvider});

  final TerminalToolRuntime runtimeAdapter;
  final Future<WorkspaceFileSystem> Function()? workspaceProvider;
  Future<TerminalExecutionResult> execute(
    String input, {
    required TerminalSessionStatus sessionStatus,
    required String Function(String source) translate,
  }) async {
    final command = input.trim();
    const forbiddenShellCharacters = {59, 60, 62, 34, 38, 39, 36, 96, 92, 124};
    // Shell punctuation is permitted only in data payloads; these branches
    // store literal text through WorkspaceFileSystem and never dispatch it.
    final workspaceDataCommand = command.startsWith('workspace write ') || command.startsWith('workspace replace ');
    if (command.length > 256 ||
        command.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f || (!workspaceDataCommand && forbiddenShellCharacters.contains(unit)))) {
      return TerminalExecutionResult.failed(translate('Only app-supported commands are accepted; shell syntax is disabled.'));
    }
    final parts = command.split(RegExp(r'\s+'));
    if (parts.length == 1 && parts.single == 'help') {
      return TerminalExecutionResult.completed(translate('Supported commands: help, status, tools, run <tool_id> <host>, workspace list [path], workspace read <path>, workspace write <path> <text>, workspace replace <path> <text>.'));
    }
    if (parts.length == 1 && parts.single == 'status') {
      final key = switch (sessionStatus) {
        TerminalSessionStatus.ready => 'Terminal ready',
        TerminalSessionStatus.running => 'Terminal busy',
        TerminalSessionStatus.exited => 'Terminal exited',
      };
      return TerminalExecutionResult.completed(translate(key));
    }
    if (parts.length == 1 && parts.single == 'tools') {
      final ready = await runtimeAdapter.readyToolIds();
      if (ready.isEmpty) return TerminalExecutionResult.completed(translate('No terminal tools are currently ready.'));
      return TerminalExecutionResult.completed(ready.map((id) => '${_toolLabel(id, translate)} ($id)').join('\n'));
    }
    if (workspaceDataCommand) return _workspaceWriteCommand(command, translate);
    if (parts.first == 'run') return _runTool(parts, translate);
    if (parts.first == 'workspace') return _workspaceCommand(parts, translate);
    return TerminalExecutionResult.failed(translate('Unknown command. Type help for supported commands.'));
  }

  Future<TerminalExecutionResult> _workspaceCommand(List<String> parts, String Function(String) translate) async {
    final createFileSystem = workspaceProvider;
    if (createFileSystem == null) return TerminalExecutionResult.failed(translate('Workspace access is not configured.'));
    if (parts.length < 2 || parts.length > 3) {
      return TerminalExecutionResult.failed(translate('Usage: workspace list [path], workspace read <path>, workspace write <path> <text>, or workspace replace <path> <text>.'));
    }
    try {
      final service = await createFileSystem();
      switch (parts[1]) {
        case 'list':
          final entries = await service.list(parts.length == 3 ? parts[2] : '', actor: WorkspaceActor.terminal);
          if (entries.isEmpty) return TerminalExecutionResult.completed(translate('The project workspace is empty.'));
          if (entries.length > 200) return TerminalExecutionResult.failed(translate('Workspace listing exceeds the Terminal display limit.'));
          return TerminalExecutionResult.completed(entries.map((entry) {
            if (entry.isDirectory) return '${entry.path}/';
            return '${entry.path} (${entry.sizeBytes ?? 0} bytes)';
          }).join('\n'));
        case 'read':
          if (parts.length != 3) return TerminalExecutionResult.failed(translate('Usage: workspace read <path>.'));
          final text = await service.readText(parts[2], actor: WorkspaceActor.terminal);
          if (text.length > 32000) return TerminalExecutionResult.failed(translate('Workspace output exceeds the Terminal display limit.'));
          return TerminalExecutionResult.completed(text);
        default:
          return TerminalExecutionResult.failed(translate('Usage: workspace list [path], workspace read <path>, workspace write <path> <text>, or workspace replace <path> <text>.'));
      }
    } on WorkspaceSecurityException catch (error) {
      return TerminalExecutionResult.failed(translate(error.message));
    } catch (_) {
      return TerminalExecutionResult.failed(translate('Workspace access failed closed.'));
    }
  }

  Future<TerminalExecutionResult> _workspaceWriteCommand(String command, String Function(String) translate) async {
    final operation = command.startsWith('workspace replace ') ? 'replace' : 'write';
    final prefix = 'workspace $operation ';
    final payload = command.substring(prefix.length);
    final separator = payload.indexOf(' ');
    if (separator <= 0) {
      return TerminalExecutionResult.failed(translate('Usage: workspace write <path> <text> or workspace replace <path> <text>.'));
    }
    final relativePath = payload.substring(0, separator);
    final contents = payload.substring(separator + 1);
    final createFileSystem = workspaceProvider;
    if (createFileSystem == null) return TerminalExecutionResult.failed(translate('Workspace access is not configured.'));
    try {
      final service = await createFileSystem();
      await service.writeText(
        relativePath,
        contents,
        actor: WorkspaceActor.terminal,
        overwrite: operation == 'replace',
      );
      return TerminalExecutionResult.completed(translate('Workspace file saved.'));
    } on WorkspaceSecurityException catch (error) {
      return TerminalExecutionResult.failed(translate(error.message));
    } catch (_) {
      return TerminalExecutionResult.failed(translate('Workspace access failed closed.'));
    }
  }

  Future<TerminalExecutionResult> _runTool(List<String> parts, String Function(String) translate) async {
    if (parts.length != 3 || !terminalSupportedToolIds.contains(parts[1])) {
      return TerminalExecutionResult.failed(translate('Usage: run <tool_id> <host>.'));
    }
    final toolId = parts[1];
    if (!isSafeTerminalHostTarget(parts[2])) {
      return TerminalExecutionResult.failed(translate('Enter one valid host only; URLs, ports and paths are not accepted.'));
    }
    return runtimeAdapter.executeTool(toolId, parts[2], translate: translate);
  }

  String _toolLabel(String id, String Function(String) translate) => switch (id) {
        'dns_lookup' => translate('DNS Lookup'),
        'tls_inspector' => translate('TLS Certificate Inspection'),
        'http_headers' => translate('HTTP Security Header Checker'),
        _ => id,
      };
}
