import 'dart:async';

import 'package:cybersecurity_assistant/core/assessment_execution_manager.dart';
import 'package:cybersecurity_assistant/core/runtime_manager.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/tool_orchestrator.dart';
import 'package:cybersecurity_assistant/core/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class _ControlledRun {
  _ControlledRun({
    required this.target,
    required this.toolIds,
    required this.authorized,
    required this.allowPrivateNetwork,
    required this.cancellationToken,
    required this.onOutcome,
  });

  final String target;
  final List<String> toolIds;
  final bool authorized;
  final bool allowPrivateNetwork;
  final RuntimeCancellationToken? cancellationToken;
  final void Function(AssessmentCheckOutcome outcome)? onOutcome;
  final Completer<AssessmentExecution> completion = Completer<AssessmentExecution>();
  final List<AssessmentCheckOutcome> emittedOutcomes = [];

  void emit(AssessmentCheckOutcome outcome) {
    emittedOutcomes.add(outcome);
    onOutcome?.call(outcome);
  }

  void complete({Iterable<AssessmentCheckOutcome>? outcomes}) {
    final now = DateTime.now().toUtc();
    completion.complete(AssessmentExecution(
      target: target,
      startedAt: now,
      completedAt: now,
      outcomes: List.unmodifiable(outcomes ?? emittedOutcomes),
    ));
  }
}

class _ControlledOrchestrator extends ToolOrchestrator {
  final List<_ControlledRun> runs = [];

  @override
  Future<ToolAvailability> availabilityForTool(String toolId) async => ToolAvailability(
        definition: toolById(toolId)!,
        status: ToolStatus.ready,
        compatibility: ToolPlatformCompatibility.bundledDartRuntimeCompatible,
        adapterRegistered: true,
        installed: true,
      );

  @override
  Future<AssessmentExecution> runAssessment({
    required String target,
    required Iterable<String> toolIds,
    required bool authorized,
    bool allowPrivateNetwork = false,
    bool includeResponseAnalysis = true,
    RuntimeCancellationToken? cancellationToken,
    void Function(AssessmentCheckOutcome outcome)? onOutcome,
  }) {
    final run = _ControlledRun(
      target: target,
      toolIds: List.unmodifiable(toolIds),
      authorized: authorized,
      allowPrivateNetwork: allowPrivateNetwork,
      cancellationToken: cancellationToken,
      onOutcome: onOutcome,
    );
    runs.add(run);
    return run.completion.future;
  }
}

Future<void> _waitUntilTerminal(AssessmentExecutionManager manager) async {
  if (manager.currentRun?.isRunning == false) return;
  final terminal = Completer<void>();
  void listener() {
    if (manager.currentRun?.isRunning == false && !terminal.isCompleted) terminal.complete();
  }

  manager.addListener(listener);
  try {
    await terminal.future.timeout(const Duration(seconds: 1));
  } finally {
    manager.removeListener(listener);
  }
}

void main() {
  test('starts once, snapshots configuration, publishes progress, and rejects a second run', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    addTearDown(manager.dispose);
    final selected = <String>['dns_lookup'];

    final started = manager.startAssessment(
      target: 'owned.example',
      toolIds: selected,
      authorized: true,
      allowPrivateNetwork: false,
    );
    selected
      ..clear()
      ..add('tls_inspector');

    expect(started.accepted, isTrue);
    expect(started.activeRunId, isNull);
    expect(manager.currentRun?.runId, started.runId);
    expect(orchestrator.runs.single.toolIds, ['dns_lookup']);
    expect(orchestrator.runs.single.target, 'owned.example');
    expect(orchestrator.runs.single.authorized, isTrue);
    expect(orchestrator.runs.single.allowPrivateNetwork, isFalse);
    expect(manager.progress?.selectedCount, 1);

    final rejected = manager.startAssessment(
      target: 'second.example',
      toolIds: const ['tls_inspector'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    expect(rejected.accepted, isFalse);
    expect(rejected.runId, isNull);
    expect(rejected.activeRunId, started.runId);
    expect(orchestrator.runs, hasLength(1));

    orchestrator.runs.single.emit(const AssessmentCheckOutcome(toolId: 'dns_lookup', status: AssessmentCheckStatus.failed, error: 'Expected fixture failure.'));
    expect(manager.progress?.failedCount, 1);
    expect(manager.currentRun?.outcomes.single.status, AssessmentCheckStatus.failed);
    orchestrator.runs.single.complete();
    await _waitUntilTerminal(manager);

    expect(manager.currentRun?.runId, started.runId);
    expect(manager.currentRun?.isRunning, isFalse);
    expect(manager.currentRun?.progress.failedCount, 1);
    expect(manager.progress, isNull);
  });

  test('official Orchestrator-generated outcomes are retained without increasing selected progress', () async {
    final orchestrator = _ControlledOrchestrator();
    final reportedResults = <ToolRunResult>[];
    final manager = AssessmentExecutionManager(orchestrator: orchestrator, onResult: reportedResults.add);
    addTearDown(manager.dispose);

    manager.startAssessment(
      target: 'owned.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final run = orchestrator.runs.single;
    final now = DateTime.now().toUtc();
    final selectedResult = ToolRunResult(
      toolId: 'dns_lookup',
      target: 'owned.example',
      summary: 'Resolved one address.',
      details: const [],
      findings: const [],
      completedAt: now,
      authorizationConfirmed: true,
    );
    final analysisResult = ToolRunResult(
      toolId: 'response_analyzer',
      target: 'owned.example',
      summary: 'Analysis completed.',
      details: const [],
      findings: const [],
      completedAt: now,
      authorizationConfirmed: false,
    );
    final selectedOutcome = AssessmentCheckOutcome(
      toolId: 'dns_lookup',
      status: AssessmentCheckStatus.completed,
      result: selectedResult,
    );
    final generatedOutcome = AssessmentCheckOutcome(
      toolId: 'response_analyzer',
      status: AssessmentCheckStatus.completed,
      result: analysisResult,
    );

    run.emit(selectedOutcome);
    expect(manager.progress?.processedCount, 1);
    expect(manager.currentRun?.outcomes.map((outcome) => outcome.toolId), ['dns_lookup']);
    run.emit(generatedOutcome);
    expect(manager.currentRun?.outcomes.map((outcome) => outcome.toolId), ['dns_lookup'],
        reason: 'Unselected outcomes are not trusted from the live callback alone.');

    run.complete(outcomes: [selectedOutcome, generatedOutcome]);
    await _waitUntilTerminal(manager);

    expect(manager.currentRun?.outcomes.map((outcome) => outcome.toolId), ['dns_lookup', 'response_analyzer']);
    expect(manager.currentRun?.progress.selectedCount, 1);
    expect(manager.currentRun?.progress.processedCount, 1);
    expect(manager.currentRun?.progress.fraction, 1);
    expect(manager.currentRun!.progress.fraction, lessThanOrEqualTo(1));
    expect(reportedResults, [selectedResult, analysisResult]);
  });

  test('analyzer evidence requires a matching successful selected result in the same terminal result', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    addTearDown(manager.dispose);
    manager.startAssessment(
      target: 'owned.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final run = orchestrator.runs.single;
    final now = DateTime.now().toUtc();
    final mismatchedEvidence = AssessmentCheckOutcome(
      toolId: 'dns_lookup',
      status: AssessmentCheckStatus.completed,
      result: ToolRunResult(
        toolId: 'tls_inspector',
        target: 'owned.example',
        summary: 'Wrong tool identity.',
        details: const [],
        findings: const [],
        completedAt: now,
      ),
    );
    final analyzer = AssessmentCheckOutcome(
      toolId: 'response_analyzer',
      status: AssessmentCheckStatus.completed,
      result: ToolRunResult(
        toolId: 'response_analyzer',
        target: 'owned.example',
        summary: 'Unsubstantiated analysis.',
        details: const [],
        findings: const [],
        completedAt: now,
      ),
    );

    run.emit(mismatchedEvidence);
    run.emit(analyzer);
    expect(manager.currentRun?.outcomes, isEmpty, reason: 'The analyzer is never accepted from live callbacks.');
    run.complete(outcomes: [mismatchedEvidence, analyzer]);
    await _waitUntilTerminal(manager);

    expect(manager.currentRun?.outcomes, isEmpty);
    expect(manager.currentRun?.progress.selectedCount, 1);
    expect(manager.currentRun?.progress.processedCount, 0);
  });

  test('analyzer result must identify the analyzer and match the evidence target', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    addTearDown(manager.dispose);
    manager.startAssessment(
      target: 'owned.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final run = orchestrator.runs.single;
    final now = DateTime.now().toUtc();
    final technical = AssessmentCheckOutcome(
      toolId: 'dns_lookup',
      status: AssessmentCheckStatus.completed,
      result: ToolRunResult(
        toolId: 'dns_lookup',
        target: 'owned.example',
        summary: 'Resolved one address.',
        details: const [],
        findings: const [],
        completedAt: now,
      ),
    );
    final wrongAnalyzerIdentity = AssessmentCheckOutcome(
      toolId: 'response_analyzer',
      status: AssessmentCheckStatus.completed,
      result: ToolRunResult(
        toolId: 'dns_lookup',
        target: 'owned.example',
        summary: 'Wrong result tool ID.',
        details: const [],
        findings: const [],
        completedAt: now,
      ),
    );
    final wrongAnalyzerTarget = AssessmentCheckOutcome(
      toolId: 'response_analyzer',
      status: AssessmentCheckStatus.completed,
      result: ToolRunResult(
        toolId: 'response_analyzer',
        target: 'other.example',
        summary: 'Wrong target.',
        details: const [],
        findings: const [],
        completedAt: now,
      ),
    );

    run.emit(technical);
    run.complete(outcomes: [technical, wrongAnalyzerIdentity, wrongAnalyzerTarget]);
    await _waitUntilTerminal(manager);

    expect(manager.currentRun?.outcomes.map((outcome) => outcome.toolId), ['dns_lookup']);
    expect(manager.currentRun?.progress.selectedCount, 1);
    expect(manager.currentRun?.progress.processedCount, 1);
  });

  test('foreign outcomes are rejected unless present in the run result contract', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    addTearDown(manager.dispose);
    manager.startAssessment(
      target: 'owned.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final run = orchestrator.runs.single;
    const unknownOutcome = AssessmentCheckOutcome(
      toolId: 'unregistered_plugin_tool',
      status: AssessmentCheckStatus.completed,
    );
    const unselectedOutcome = AssessmentCheckOutcome(
      toolId: 'tls_inspector',
      status: AssessmentCheckStatus.failed,
      error: 'Not part of this run.',
    );
    const selectedOutcome = AssessmentCheckOutcome(
      toolId: 'dns_lookup',
      status: AssessmentCheckStatus.failed,
      error: 'Expected fixture failure.',
    );

    run.emit(unknownOutcome);
    run.emit(unselectedOutcome);
    expect(manager.currentRun?.outcomes, isEmpty);
    expect(manager.progress?.processedCount, 0);

    run.emit(selectedOutcome);
    expect(manager.currentRun?.outcomes.map((outcome) => outcome.toolId), ['dns_lookup']);
    expect(manager.progress?.processedCount, 1);
    // Neither the unknown ID nor a registered-but-unselected callback is in
    // the Orchestrator's authoritative AssessmentExecution result.
    run.complete(outcomes: [selectedOutcome, unselectedOutcome, unknownOutcome]);
    await _waitUntilTerminal(manager);

    expect(manager.currentRun?.outcomes.map((outcome) => outcome.toolId), ['dns_lookup']);
    expect(manager.currentRun?.progress.selectedCount, 1);
    expect(manager.currentRun?.progress.processedCount, 1);
    expect(manager.progress, isNull);
  });

  test('late progress and cancellation from a completed run cannot affect the next run', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    addTearDown(manager.dispose);

    final first = manager.startAssessment(
      target: 'first.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final firstCall = orchestrator.runs.single;
    firstCall.complete();
    await _waitUntilTerminal(manager);

    final second = manager.startAssessment(
      target: 'second.example',
      toolIds: const ['tls_inspector'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    expect(second.accepted, isTrue);
    expect(second.runId, isNot(first.runId));

    firstCall.emit(AssessmentCheckOutcome(
      toolId: 'dns_lookup',
      status: AssessmentCheckStatus.completed,
      result: ToolRunResult(
        toolId: 'dns_lookup',
        target: 'first.example',
        summary: 'Late but otherwise valid result.',
        details: const [],
        findings: const [],
        completedAt: DateTime.now().toUtc(),
      ),
    ));
    expect(manager.cancelRun(first.runId!), isFalse);
    expect(manager.activeRun?.runId, second.runId);
    expect(manager.progress?.runId, second.runId);
    expect(manager.progress?.processedCount, 0);

    final secondCall = orchestrator.runs.last;
    final secondResult = ToolRunResult(
      toolId: 'tls_inspector',
      target: 'second.example',
      summary: 'TLS check completed.',
      details: const [],
      findings: const [],
      completedAt: DateTime.now().toUtc(),
    );
    secondCall.emit(AssessmentCheckOutcome(
      toolId: 'tls_inspector',
      status: AssessmentCheckStatus.completed,
      result: secondResult,
    ));
    expect(manager.progress?.completedCount, 1);
    secondCall.complete();
    await _waitUntilTerminal(manager);
    expect(manager.currentRun?.runId, second.runId);
    expect(manager.progress, isNull);
  });

  test('cancellation is run-scoped and terminal state is recorded once', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    addTearDown(manager.dispose);

    final started = manager.startAssessment(
      target: 'owned.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final call = orchestrator.runs.single;
    expect(manager.cancelRun('not-the-active-id'), isFalse);
    expect(call.cancellationToken?.isCancelled, isFalse);

    expect(manager.cancelRun(started.runId!), isTrue);
    expect(manager.cancelRun(started.runId!), isFalse, reason: 'Repeated cancellation requests are idempotent.');
    expect(call.cancellationToken?.isCancelled, isTrue);
    call.emit(const AssessmentCheckOutcome(toolId: 'dns_lookup', status: AssessmentCheckStatus.cancelled));
    call.complete();
    await _waitUntilTerminal(manager);

    expect(manager.currentRun?.isRunning, isFalse);
    expect(manager.currentRun?.wasCancelled, isTrue);
    expect(manager.currentRun?.progress.cancelledCount, 1);
    expect(manager.cancelRun(started.runId!), isFalse, reason: 'Terminal cancellation is not applied twice.');
  });

  test('MainShell shutdown requests cooperative cancellation and waits for cleanup', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(orchestrator: orchestrator);
    manager.startAssessment(
      target: 'owned.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final call = orchestrator.runs.single;

    var shutdownCompleted = false;
    final shutdown = manager.shutdown().then((_) => shutdownCompleted = true);
    expect(call.cancellationToken?.isCancelled, isTrue);
    expect(shutdownCompleted, isFalse, reason: 'The owner waits until the cooperative run future settles.');

    call.emit(const AssessmentCheckOutcome(toolId: 'dns_lookup', status: AssessmentCheckStatus.cancelled));
    call.complete();
    await shutdown;
    expect(shutdownCompleted, isTrue);
    expect(manager.currentRun?.wasCancelled, isTrue);
  });

  test('a throwing result callback cannot prevent terminal cleanup', () async {
    final orchestrator = _ControlledOrchestrator();
    final manager = AssessmentExecutionManager(
      orchestrator: orchestrator,
      onResult: (_) => throw StateError('Fixture callback failure.'),
    );
    addTearDown(manager.dispose);

    final started = manager.startAssessment(
      target: 'owned.example',
      toolIds: const ['dns_lookup'],
      authorized: true,
      allowPrivateNetwork: false,
    );
    final now = DateTime.now().toUtc();
    final result = ToolRunResult(
      toolId: 'dns_lookup',
      target: 'owned.example',
      summary: 'Fixture result.',
      details: const [],
      findings: const [],
      completedAt: now,
      authorizationConfirmed: true,
    );
    orchestrator.runs.single.emit(AssessmentCheckOutcome(toolId: 'dns_lookup', status: AssessmentCheckStatus.completed, result: result));
    orchestrator.runs.single.complete();
    await _waitUntilTerminal(manager);

    expect(manager.currentRun?.runId, started.runId);
    expect(manager.currentRun?.isRunning, isFalse);
    expect(manager.currentRun?.outcomes.single.result, same(result));
  });
}
