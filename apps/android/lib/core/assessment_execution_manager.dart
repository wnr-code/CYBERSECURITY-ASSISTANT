import 'dart:async';

import 'package:flutter/foundation.dart';

import 'assessment_progress.dart';
import 'diagnostics.dart';
import 'runtime_manager.dart';
import 'security_tools.dart';
import 'tool_orchestrator.dart';

/// Presentation-safe state for the latest application-owned Assessment run.
class AssessmentRunView {
  AssessmentRunView({
    required this.progress,
    required this.target,
    required Iterable<String> selectedToolIds,
    required this.authorized,
    required this.allowPrivateNetwork,
    required Iterable<AssessmentCheckOutcome> outcomes,
    this.cancellationRequested = false,
    this.error,
    this.wasCancelled = false,
  })  : selectedToolIds = List.unmodifiable(selectedToolIds),
        outcomes = List.unmodifiable(outcomes);

  final AssessmentProgressSnapshot progress;
  final String target;
  final List<String> selectedToolIds;
  final bool authorized;
  final bool allowPrivateNetwork;
  final List<AssessmentCheckOutcome> outcomes;
  final bool cancellationRequested;
  final String? error;
  final bool wasCancelled;

  String get runId => progress.runId;
  bool get isRunning => progress.isRunning;

  AssessmentRunView copyWith({
    AssessmentProgressSnapshot? progress,
    Iterable<AssessmentCheckOutcome>? outcomes,
    bool? cancellationRequested,
    String? error,
    bool clearError = false,
    bool? wasCancelled,
  }) =>
      AssessmentRunView(
        progress: progress ?? this.progress,
        target: target,
        selectedToolIds: selectedToolIds,
        authorized: authorized,
        allowPrivateNetwork: allowPrivateNetwork,
        outcomes: outcomes ?? this.outcomes,
        cancellationRequested: cancellationRequested ?? this.cancellationRequested,
        error: clearError ? null : error ?? this.error,
        wasCancelled: wasCancelled ?? this.wasCancelled,
      );
}

class AssessmentStartResult {
  const AssessmentStartResult.started(this.runId) : accepted = true;
  const AssessmentStartResult.rejected(this.activeRunId)
      : accepted = false,
        runId = null;

  final bool accepted;
  final String? runId;
  final String? activeRunId;
}

/// MainShell-owned execution lifecycle. A Runner may come and go; this manager
/// owns the cancellation token, immutable run configuration, outcomes, and the
/// single progress coordinator for the lifetime of MainShell.
class AssessmentExecutionManager extends ChangeNotifier {
  AssessmentExecutionManager({
    required ToolOrchestrator orchestrator,
    ValueChanged<ToolRunResult>? onResult,
  })  : _orchestrator = orchestrator,
        _onResult = onResult;

  final ToolOrchestrator _orchestrator;
  final ValueChanged<ToolRunResult>? _onResult;
  final AssessmentProgressCoordinator _progressCoordinator = AssessmentProgressCoordinator();

  AssessmentRunView? _currentRun;
  RuntimeCancellationToken? _cancellationToken;
  Future<void>? _executionFuture;
  Future<void>? _shutdownFuture;
  bool _shuttingDown = false;
  bool _disposed = false;

  AssessmentRunView? get currentRun => _currentRun;
  AssessmentRunView? get activeRun => _currentRun?.isRunning == true ? _currentRun : null;
  AssessmentProgressSnapshot? get progress => _progressCoordinator.current;
  bool get isRunning => activeRun != null;

  Future<ToolAvailability> availabilityForTool(String toolId) => _orchestrator.availabilityForTool(toolId);

  AssessmentStartResult startAssessment({
    required String target,
    required Iterable<String> toolIds,
    required bool authorized,
    required bool allowPrivateNetwork,
  }) {
    final active = activeRun;
    if (_disposed || _shuttingDown || active != null) {
      return AssessmentStartResult.rejected(active?.runId);
    }

    // Freeze all user-selected configuration before the first asynchronous gap.
    final selectedToolIds = List<String>.unmodifiable(toolIds.toSet().where((id) => id != 'response_analyzer'));
    final runTarget = target;
    final runAuthorized = authorized;
    final runAllowsPrivateNetwork = allowPrivateNetwork;
    final cancellationToken = RuntimeCancellationToken();
    final initial = _progressCoordinator.beginRun(selectedCount: selectedToolIds.length);
    _cancellationToken = cancellationToken;
    _currentRun = AssessmentRunView(
      progress: initial,
      target: runTarget,
      selectedToolIds: selectedToolIds,
      authorized: runAuthorized,
      allowPrivateNetwork: runAllowsPrivateNetwork,
      outcomes: const [],
    );
    _notifySafely();

    final execution = _execute(
      initial.runId,
      target: runTarget,
      toolIds: selectedToolIds,
      authorized: runAuthorized,
      allowPrivateNetwork: runAllowsPrivateNetwork,
      cancellationToken: cancellationToken,
    );
    _executionFuture = execution;
    unawaited(execution);
    return AssessmentStartResult.started(initial.runId);
  }

  bool cancelRun(String runId) {
    final run = activeRun;
    if (run == null || run.runId != runId || run.cancellationRequested) return false;
    _currentRun = run.copyWith(cancellationRequested: true);
    _cancellationToken?.cancel();
    _notifySafely();
    return true;
  }

  Future<void> _execute(
    String runId, {
    required String target,
    required List<String> toolIds,
    required bool authorized,
    required bool allowPrivateNetwork,
    required RuntimeCancellationToken cancellationToken,
  }) async {
    String? errorMessage;
    try {
      final execution = await _orchestrator.runAssessment(
        target: target,
        toolIds: toolIds,
        authorized: authorized,
        allowPrivateNetwork: allowPrivateNetwork,
        cancellationToken: cancellationToken,
        onOutcome: (outcome) => _acceptOutcome(runId, toolIds, outcome),
      );
      _acceptReturnedOutcomes(runId, toolIds, execution.outcomes);
    } catch (error, stack) {
      errorMessage = error.toString();
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
    } finally {
      _finishRun(runId, toolIds, cancellationToken, errorMessage: errorMessage);
    }
  }

  /// Reconcile the Orchestrator's authoritative terminal outcome list. Its
  /// AssessmentExecution includes both requested checks and any official
  /// derived checks (currently response analysis). Unselected outcomes are
  /// accepted only from this run-scoped result, and unknown registry IDs are
  /// discarded. Progress remains scoped to the user's selected tool IDs.
  void _acceptReturnedOutcomes(String runId, List<String> toolIds, List<AssessmentCheckOutcome> outcomes) {
    if (_disposed) return;
    final run = activeRun;
    if (run == null || run.runId != runId) return;

    final selected = toolIds.toSet();
    // Use only completed, selected technical results from this exact returned
    // AssessmentExecution as evidence that the Orchestrator could have invoked
    // its automatic analyzer. Check both identities because the outcome and its
    // result are separate model objects.
    final technicalEvidence = outcomes.where((outcome) {
      if (outcome.toolId == 'response_analyzer' ||
          !selected.contains(outcome.toolId) ||
          _orchestrator.registry.byId(outcome.toolId) == null ||
          outcome.status != AssessmentCheckStatus.completed) {
        return false;
      }
      final result = outcome.result;
      return result != null && result.toolId == outcome.toolId;
    }).toList(growable: false);
    final hasTechnicalResult = technicalEvidence.isNotEmpty;
    final acceptedByTool = <String, AssessmentCheckOutcome>{};
    for (final outcome in outcomes) {
      final isSelectedTechnical = outcome.toolId != 'response_analyzer' && selected.contains(outcome.toolId);
      final isValidAnalyzer = outcome.toolId == 'response_analyzer' &&
          hasTechnicalResult &&
          _orchestrator.registry.byId('response_analyzer') != null &&
          _hasConsistentResult(outcome) &&
          (outcome.status != AssessmentCheckStatus.completed ||
              outcome.result!.target == technicalEvidence.first.result!.target);
      if ((!isSelectedTechnical && !isValidAnalyzer) ||
          _orchestrator.registry.byId(outcome.toolId) == null ||
          !_hasConsistentResult(outcome)) {
        continue;
      }
      // Orchestrator executes each tool at most once. Defensively collapse any
      // duplicate terminal entries while preserving the first-seen order.
      acceptedByTool.putIfAbsent(outcome.toolId, () => outcome);
    }
    final acceptedOutcomes = acceptedByTool.values.toList(growable: false);
    final progress = _progressFor(runId, selected, acceptedOutcomes, isRunning: true);
    if (!_progressCoordinator.accept(progress)) return;

    final reportedResults = run.outcomes.map((outcome) => outcome.result).whereType<ToolRunResult>().toList();
    for (final outcome in acceptedOutcomes) {
      final result = outcome.result;
      if (result == null || reportedResults.any((reported) => identical(reported, result))) continue;
      reportedResults.add(result);
      _reportResultSafely(result);
    }

    _currentRun = run.copyWith(progress: progress, outcomes: acceptedOutcomes);
    _notifySafely();
  }

  AssessmentProgressSnapshot _progressFor(
    String runId,
    Set<String> selectedToolIds,
    Iterable<AssessmentCheckOutcome> outcomes, {
    required bool isRunning,
  }) =>
      AssessmentProgressSnapshot(
        runId: runId,
        isRunning: isRunning,
        selectedCount: selectedToolIds.length,
        completedCount: _countSelectedOutcomes(selectedToolIds, outcomes, AssessmentCheckStatus.completed),
        failedCount: _countSelectedOutcomes(selectedToolIds, outcomes, AssessmentCheckStatus.failed),
        skippedCount: _countSelectedOutcomes(selectedToolIds, outcomes, AssessmentCheckStatus.skipped),
        cancelledCount: _countSelectedOutcomes(selectedToolIds, outcomes, AssessmentCheckStatus.cancelled),
      );

  bool _hasConsistentResult(AssessmentCheckOutcome outcome) {
    final result = outcome.result;
    if (outcome.status == AssessmentCheckStatus.completed) {
      return result != null && result.toolId == outcome.toolId;
    }
    return result == null;
  }

  int _countSelectedOutcomes(
    Set<String> selectedToolIds,
    Iterable<AssessmentCheckOutcome> outcomes,
    AssessmentCheckStatus status,
  ) {
    final counted = <String>{};
    for (final outcome in outcomes) {
      if (selectedToolIds.contains(outcome.toolId) && outcome.status == status) counted.add(outcome.toolId);
    }
    return counted.length.clamp(0, selectedToolIds.length).toInt();
  }

  void _acceptOutcome(String runId, List<String> toolIds, AssessmentCheckOutcome outcome) {
    if (_disposed) return;
    final run = activeRun;
    if (run == null ||
        run.runId != runId ||
        outcome.toolId == 'response_analyzer' ||
        !toolIds.contains(outcome.toolId) ||
        _orchestrator.registry.byId(outcome.toolId) == null ||
        !_hasConsistentResult(outcome)) {
      return;
    }

    final outcomes = [...run.outcomes];
    final existingIndex = outcomes.indexWhere((item) => item.toolId == outcome.toolId);
    if (existingIndex < 0) {
      outcomes.add(outcome);
    } else {
      outcomes[existingIndex] = outcome;
    }
    final snapshot = _progressFor(runId, toolIds.toSet(), outcomes, isRunning: true);
    if (!_progressCoordinator.accept(snapshot)) return;
    _currentRun = run.copyWith(progress: snapshot, outcomes: outcomes);

    final result = outcome.result;
    if (result != null) _reportResultSafely(result);
    _notifySafely();
  }

  void _reportResultSafely(ToolRunResult result) {
    final callback = _onResult;
    if (callback == null) return;
    try {
      callback(result);
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
    }
  }

  void _finishRun(
    String runId,
    List<String> toolIds,
    RuntimeCancellationToken cancellationToken, {
    required String? errorMessage,
  }) {
    final run = activeRun;
    if (run == null || run.runId != runId) return;

    final outcomes = run.outcomes;
    final terminal = _progressFor(runId, toolIds.toSet(), outcomes, isRunning: false);
    if (!_progressCoordinator.accept(terminal)) return;

    final wasCancelled = cancellationToken.isCancelled || outcomes.any((item) => item.status == AssessmentCheckStatus.cancelled);
    _currentRun = run.copyWith(
      progress: terminal,
      error: errorMessage,
      wasCancelled: wasCancelled,
    );
    if (_cancellationToken == cancellationToken) _cancellationToken = null;
    _executionFuture = null;
    _notifySafely();
  }

  void _notifySafely() {
    if (_disposed) return;
    try {
      notifyListeners();
    } catch (error, stack) {
      // A view listener is observational and cannot break run execution/cleanup.
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
    }
  }

  /// Request cooperative cancellation and wait before MainShell releases the
  /// stores/package manager used by the in-flight Orchestrator run.
  Future<void> shutdown() {
    return _shutdownFuture ??= _shutdown();
  }

  Future<void> _shutdown() async {
    _shuttingDown = true;
    final active = activeRun;
    if (active != null) {
      _currentRun = active.copyWith(cancellationRequested: true);
      _cancellationToken?.cancel();
    }
    final execution = _executionFuture;
    if (execution != null) await execution;
    dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _shuttingDown = true;
    _disposed = true;
    // Also cover direct disposal; normal MainShell teardown awaits shutdown().
    _cancellationToken?.cancel();
    super.dispose();
  }
}
