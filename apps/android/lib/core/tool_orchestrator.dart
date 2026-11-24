import 'diagnostics.dart';
import 'security_tools.dart';
import 'tool_registry.dart';

class ToolInvocation {
  const ToolInvocation({
    required this.toolId,
    required this.target,
    required this.authorized,
    this.allowPrivateNetwork = false,
    this.priorResults = const [],
  });

  final String toolId;
  final String target;
  final bool authorized;
  final bool allowPrivateNetwork;
  final List<ToolRunResult> priorResults;
}

class ToolOrchestrationException implements Exception {
  const ToolOrchestrationException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum AssessmentCheckStatus { completed, failed }

class AssessmentCheckOutcome {
  const AssessmentCheckOutcome({required this.toolId, required this.status, this.result, this.error});
  final String toolId;
  final AssessmentCheckStatus status;
  final ToolRunResult? result;
  final String? error;
}

class AssessmentExecution {
  const AssessmentExecution({required this.target, required this.startedAt, required this.completedAt, required this.outcomes});
  final String target;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<AssessmentCheckOutcome> outcomes;

  int get completedCount => outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.completed).length;
  int get failedCount => outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.failed).length;
}

/// The only dispatch boundary for model- or UI-originated tool requests.
/// It accepts typed registry IDs only: no free-form shell or executable input.
class ToolOrchestrator {
  ToolOrchestrator({SecurityTools? tools}) : _tools = tools ?? SecurityTools();
  final SecurityTools _tools;

  Future<ToolRunResult> execute(ToolInvocation invocation) async {
    final definition = toolById(invocation.toolId);
    if (definition == null || definition.status != ToolStatus.available) {
      throw const ToolOrchestrationException('Requested tool is not available in the local registry.');
    }

    try {
      switch (definition.id) {
        case 'dns_lookup':
          return await _tools.runDnsLookup(invocation.target, authorized: invocation.authorized);
        case 'tls_inspector':
          return await _tools.inspectTls(
            invocation.target,
            authorized: invocation.authorized,
            allowPrivateNetwork: invocation.allowPrivateNetwork,
          );
        case 'http_headers':
          return await _tools.checkHttpHeaders(
            invocation.target,
            authorized: invocation.authorized,
            allowPrivateNetwork: invocation.allowPrivateNetwork,
          );
        case 'response_analyzer':
          return _analyze(invocation);
      }
      throw const ToolOrchestrationException('Registry entry has no execution adapter.');
    } on Exception catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.network);
      rethrow;
    }
  }

  /// Runs selected registered checks sequentially, retaining each failure and
  /// continuing so a partial assessment is still useful and honestly reported.
  Future<AssessmentExecution> runAssessment({
    required String target,
    required Iterable<String> toolIds,
    required bool authorized,
    bool allowPrivateNetwork = false,
    bool includeResponseAnalysis = true,
    void Function(AssessmentCheckOutcome outcome)? onOutcome,
  }) async {
    final ids = toolIds.toSet().where((id) => id != 'response_analyzer').toList();
    if (ids.isEmpty) throw const ToolOrchestrationException('Select at least one technical check.');
    final startedAt = DateTime.now().toUtc();
    final outcomes = <AssessmentCheckOutcome>[];
    final results = <ToolRunResult>[];

    Future<void> runOne(
      String toolId, {
      required String checkTarget,
      required bool checkAuthorized,
      bool allowPrivate = false,
      List<ToolRunResult> prior = const [],
    }) async {
      late final AssessmentCheckOutcome outcome;
      try {
        final result = await execute(ToolInvocation(
          toolId: toolId,
          target: checkTarget,
          authorized: checkAuthorized,
          allowPrivateNetwork: allowPrivate,
          priorResults: prior,
        ));
        results.add(result);
        outcome = AssessmentCheckOutcome(toolId: toolId, status: AssessmentCheckStatus.completed, result: result);
      } on Exception catch (error) {
        outcome = AssessmentCheckOutcome(toolId: toolId, status: AssessmentCheckStatus.failed, error: error.toString());
      }
      outcomes.add(outcome);
      onOutcome?.call(outcome);
    }

    for (final id in ids) {
      await runOne(
        id,
        checkTarget: target,
        checkAuthorized: authorized,
        allowPrivate: allowPrivateNetwork,
      );
    }
    if (includeResponseAnalysis && results.isNotEmpty) {
      await runOne(
        'response_analyzer',
        checkTarget: results.first.target,
        checkAuthorized: false,
        prior: results.toList(growable: false),
      );
    }
    return AssessmentExecution(
      target: results.isEmpty ? target : results.first.target,
      startedAt: startedAt,
      completedAt: DateTime.now().toUtc(),
      outcomes: List.unmodifiable(outcomes),
    );
  }

  ToolRunResult _analyze(ToolInvocation invocation) {
    final checks = invocation.priorResults.where((result) => result.toolId != 'response_analyzer').toList();
    if (checks.isEmpty) {
      throw const ToolOrchestrationException('Run and save at least one local check before analysis.');
    }
    final target = invocation.target.isNotEmpty ? invocation.target : checks.first.target;
    final scopedResults = checks.where((result) => result.target == target).toList();
    if (scopedResults.isEmpty) {
      throw const ToolOrchestrationException('No saved results match the requested target.');
    }
    return _tools.analyze(scopedResults, target: target);
  }
}
