import 'package:cybersecurity_assistant/core/activity_timeline.dart';
import 'package:cybersecurity_assistant/core/terminal_process_executor.dart';
import 'package:cybersecurity_assistant/core/terminal_runtime_adapter.dart';
import 'dart:io';

import 'package:cybersecurity_assistant/core/terminal_session_manager.dart';
import 'package:cybersecurity_assistant/core/workspace_file_system.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTerminalRuntime implements TerminalToolRuntime {
  final calls = <String>[];
  List<String> ready = const ['dns_lookup'];

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
    return TerminalExecutionResult.completed('fixture output');
  }
}

void main() {
  test('terminal accepts only built-in commands and a typed allowlisted tool request', () async {
    final runtime = _FakeTerminalRuntime();
    final executor = SafeTerminalProcessExecutor(runtimeAdapter: runtime);
    String translate(String source) => source;

    final help = await executor.execute('help', sessionStatus: TerminalSessionStatus.ready, translate: translate);
    expect(help.succeeded, isTrue);
    expect(help.output, contains('run <tool_id> <host>'));

    final run = await executor.execute(
      'run dns_lookup owned.example',
      sessionStatus: TerminalSessionStatus.ready,
      translate: translate,
    );
    expect(run.output, 'fixture output');
    expect(runtime.calls, ['dns_lookup:owned.example']);

    final shell = await executor.execute(
      'run dns_lookup owned.example; id',
      sessionStatus: TerminalSessionStatus.ready,
      translate: translate,
    );
    expect(shell.succeeded, isFalse);
    expect(runtime.calls, hasLength(1));

    final invalidTarget = await executor.execute(
      'run dns_lookup https://owned.example/path',
      sessionStatus: TerminalSessionStatus.ready,
      translate: translate,
    );
    expect(invalidTarget.succeeded, isFalse);
    expect(runtime.calls, hasLength(1));
  });

  test('Terminal workspace commands use the scoped filesystem API and explicit authorization', () async {
    final sandbox = await Directory.systemTemp.createTemp('terminal-workspace-');
    addTearDown(() async { if (await sandbox.exists()) await sandbox.delete(recursive: true); });
    final root = Directory('${sandbox.path}/projects');
    await root.create();
    await File('${root.path}/notes.md').writeAsString('project notes');
    final authorizations = <WorkspaceAction>[];
    final workspace = await WorkspaceFileSystem.fromRoot(
      root,
      protectedRoots: [Directory('${sandbox.path}/private')],
      authorize: ({required actor, required action, required relativePath}) async {
        expect(actor, WorkspaceActor.terminal);
        authorizations.add(action);
        return true;
      },
    );
    final executor = SafeTerminalProcessExecutor(runtimeAdapter: _FakeTerminalRuntime(), workspaceProvider: () async => workspace);

    final listed = await executor.execute('workspace list', sessionStatus: TerminalSessionStatus.ready, translate: (text) => text);
    expect(listed.output, contains('notes.md'));
    final read = await executor.execute('workspace read notes.md', sessionStatus: TerminalSessionStatus.ready, translate: (text) => text);
    expect(read.output, 'project notes');
    final created = await executor.execute(
      'workspace write demo.txt literal; rm is stored as text',
      sessionStatus: TerminalSessionStatus.ready,
      translate: (text) => text,
    );
    expect(created.succeeded, isTrue);
    expect(await File('${root.path}/demo.txt').readAsString(), 'literal; rm is stored as text');
    final replaced = await executor.execute(
      'workspace replace demo.txt updated source',
      sessionStatus: TerminalSessionStatus.ready,
      translate: (text) => text,
    );
    expect(replaced.succeeded, isTrue);
    expect(await File('${root.path}/demo.txt').readAsString(), 'updated source');
    final traversal = await executor.execute('workspace read ../private/secret.txt', sessionStatus: TerminalSessionStatus.ready, translate: (text) => text);
    expect(traversal.succeeded, isFalse);
    expect(authorizations, [WorkspaceAction.list, WorkspaceAction.read, WorkspaceAction.write, WorkspaceAction.write]);
  });

  test('terminal blocks tool execution when its audit store is unavailable', () async {
    final session = TerminalSessionManager();
    addTearDown(session.dispose);
    var executed = false;

    await session.submit(
      'run dns_lookup owned.example',
      auditLabel: 'run',
      translate: (source) => source,
      execute: (_) async {
        executed = true;
        return const TerminalExecutionResult.completed('should not execute');
      },
    );

    expect(executed, isFalse);
    expect(session.entries.single.status, TerminalEntryStatus.failed);
    expect(session.entries.single.output, contains('tool execution is disabled'));
    expect(session.auditPersistenceAvailable, isFalse);
  });

  test('terminal session preserves its transcript until explicit Exit and audits commands', () async {
    final activity = MemoryActivityHistoryStore();
    final session = TerminalSessionManager(activityStore: activity);
    addTearDown(session.dispose);

    await session.submit(
      'help',
      auditLabel: 'help',
      translate: (source) => source,
      execute: (_) async => const TerminalExecutionResult.completed('help output'),
    );
    expect(session.status, TerminalSessionStatus.ready);
    expect(session.entries, hasLength(1));
    expect(session.entries.single.output, 'help output');

    await session.submit(
      'tools',
      auditLabel: 'tools',
      translate: (source) => source,
      execute: (_) async => const TerminalExecutionResult.completed('tool list'),
    );
    expect(session.entries, hasLength(2));

    await session.exit();
    expect(session.status, TerminalSessionStatus.exited);
    final audit = await activity.loadActivities(limit: 10, toolId: 'terminal_workspace');
    expect(audit, hasLength(3));
    expect(audit.any((event) => event.summary == 'Terminal session action: session_exit.'), isTrue);

    session.startNewSession();
    expect(session.status, TerminalSessionStatus.ready);
    expect(session.entries, isEmpty);
  });
}
