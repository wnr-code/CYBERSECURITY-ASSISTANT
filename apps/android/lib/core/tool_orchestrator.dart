import 'dart:convert';
import 'dart:io';

import 'activity_timeline.dart';
import 'diagnostics.dart';
import 'dart_security_tools_runtime.dart';
import 'runtime_manager.dart';
import 'security_tools.dart';
import 'tool_registry.dart';
import 'tool_result_codec.dart';

class ToolInvocation {
  const ToolInvocation({
    required this.toolId,
    required this.target,
    required this.authorized,
    this.allowPrivateNetwork = false,
    this.priorResults = const [],
    this.cancellationToken,
    this.parentActivityId,
  });

  final String toolId;
  final String target;
  final bool authorized;
  final bool allowPrivateNetwork;
  final List<ToolRunResult> priorResults;
  final RuntimeCancellationToken? cancellationToken;
  final String? parentActivityId;
}

class ToolOrchestrationException implements Exception {
  const ToolOrchestrationException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum AssessmentCheckStatus { completed, failed, cancelled }

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
  int get cancelledCount => outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.cancelled).length;
}

/// The only dispatch boundary for model- or UI-originated tool requests.
/// It accepts typed registry IDs only: no free-form shell or executable input.
class ToolOrchestrator {
  ToolOrchestrator({
    SecurityTools? tools,
    RuntimeManager? runtimeManager,
    this.activityStore,
    this.onActivity,
  })  : _tools = tools ?? SecurityTools() {
    _runtimeManager = runtimeManager != null
        ? Future.value(runtimeManager)
        : tools == null
            ? sharedRuntimeManager
            : _createRuntimeManager(_tools);
  }

  static Future<RuntimeManager>? _sharedRuntimeManager;
  static Future<RuntimeManager> get sharedRuntimeManager =>
      _sharedRuntimeManager ??= _createRuntimeManager(SecurityTools());

  final SecurityTools _tools;
  final ActivityHistoryStore? activityStore;
  final void Function(ActivityEvent event)? onActivity;
  static int _activitySequence = 0;
  late final Future<RuntimeManager> _runtimeManager;

  static Future<RuntimeManager> _createRuntimeManager(SecurityTools tools) async {
    final environment = await RuntimeEnvironment.detect();
    final onAndroid = environment.platform.toLowerCase() == 'android';
    return RuntimeManager(
      environment: environment,
      store: onAndroid ? FileRuntimeStateStore() : MemoryRuntimeStateStore(),
      adapters: [DartSecurityToolsRuntime(tools: tools)],
      supportDirectoryProvider: onAndroid ? null : () async => Directory.systemTemp,
    );
  }

  Future<RuntimeManager> get runtimeManager async => _runtimeManager;

  static String _newActivityId(String prefix) =>
      '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-${++_activitySequence}';

  static String _boundedActivitySummary(String value) => sanitizeActivitySummary(value);

  Future<void> _emitActivity(ActivityEvent event) async {
    final validated = event.sanitizedForStorage().validated();
    try {
      await activityStore?.upsertActivity(validated);
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.database);
    }
    try {
      onActivity?.call(validated);
    } catch (error, stack) {
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.runtime);
    }
  }

  Future<ToolStatus> statusForTool(String toolId) async {
    final definition = toolById(toolId);
    if (definition == null) return ToolStatus.unsupported;
    if (definition.status == ToolStatus.unsupported) return ToolStatus.unsupported;
    final runtimeId = definition.runtimeId;
    if (runtimeId == null) return ToolStatus.environmentRequired;
    final manager = await _runtimeManager;
    final discoveries = await manager.discover();
    final discovery = _findDiscovery(discoveries, runtimeId);
    if (discovery == null) return ToolStatus.unsupported;
    return switch (discovery.status) {
      RuntimeDiscoveryStatus.available => ToolStatus.available,
      RuntimeDiscoveryStatus.notInstalled => ToolStatus.notInstalled,
      RuntimeDiscoveryStatus.unsupported => ToolStatus.unsupported,
      RuntimeDiscoveryStatus.environmentRequired => ToolStatus.environmentRequired,
    };
  }

  RuntimeDiscovery? _findDiscovery(List<RuntimeDiscovery> discoveries, String runtimeId) {
    for (final discovery in discoveries) {
      if (discovery.descriptor.id == runtimeId) return discovery;
    }
    return null;
  }

  Future<ToolRunResult> execute(ToolInvocation invocation) async {
    final definition = toolById(invocation.toolId);
    if (definition == null || definition.status != ToolStatus.available) {
      throw const ToolOrchestrationException('Requested tool is not available in the local registry.');
    }
    final runtimeId = definition.runtimeId;
    if (runtimeId == null) throw const ToolOrchestrationException('No runtime is registered for this tool.');
    if (invocation.target.length > 2048 || invocation.priorResults.length > 16) {
      throw const ToolOrchestrationException('Tool input exceeds the allowed size or item limit.');
    }
    for (final result in invocation.priorResults) {
      if (result.target.length > 2048 || utf8.encode(encodeToolRunResult(result)).length > 65536) {
        throw const ToolOrchestrationException('Saved result exceeds the analysis input limit.');
      }
    }
    if (definition.id == 'response_analyzer') {
      final checks = invocation.priorResults.where((result) => result.toolId != 'response_analyzer').toList();
      if (checks.isEmpty) throw const ToolOrchestrationException('Run and save at least one local check before analysis.');
      final target = invocation.target.isNotEmpty ? invocation.target : checks.first.target;
      if (!checks.any((result) => result.target == target)) {
        throw const ToolOrchestrationException('No saved results match the requested target.');
      }
    }

    final requiredCapabilities = <RuntimeCapability>{};
    for (final name in definition.requiredCapabilities) {
      final matches = RuntimeCapability.values.where((capability) => capability.name == name);
      if (matches.isEmpty) throw const ToolOrchestrationException('Tool registry contains an unsupported capability.');
      requiredCapabilities.add(matches.first);
    }
    final input = <String, Object?>{'target': invocation.target};
    if (definition.id == 'tls_inspector' || definition.id == 'http_headers') {
      input['allowPrivateNetwork'] = invocation.allowPrivateNetwork;
    }
    if (definition.id == 'response_analyzer') {
      input['priorResults'] = invocation.priorResults.map(encodeToolRunResult).toList(growable: false);
    }

    final activityStartedAt = DateTime.now().toUtc();
    final activity = ActivityEvent(
      eventId: _newActivityId('tool'),
      kind: ActivityKind.tool,
      parentEventId: invocation.parentActivityId,
      toolId: definition.id,
      target: sanitizeActivityTarget(invocation.target),
      status: ActivityStatus.started,
      startedAt: activityStartedAt,
    );
    await _emitActivity(activity);
    try {
      final manager = await _runtimeManager;
      final discovery = _findDiscovery(await manager.discover(), runtimeId);
      if (discovery == null || discovery.status != RuntimeDiscoveryStatus.available) {
        final reason = discovery?.reason ?? 'No compatible runtime adapter is registered.';
        throw ToolOrchestrationException(reason);
      }
      await _emitActivity(activity.copyWith(status: ActivityStatus.running));
      final execution = await manager.executeTool(
        runtimeId: runtimeId,
        toolId: definition.id,
        input: input,
        requiredCapabilities: requiredCapabilities,
        networkAuthorized: invocation.authorized,
        cancellationToken: invocation.cancellationToken,
      );
      const resultFields = {'toolId', 'target', 'summary', 'details', 'findings', 'completedAt', 'authorizationConfirmed'};
      if (execution.output.keys.toSet().length != resultFields.length || !execution.output.keys.toSet().containsAll(resultFields)) {
        throw const ToolOrchestrationException('Runtime returned an invalid tool result shape.');
      }
      final result = decodeToolRunResult(jsonEncode(execution.output));
      if (result.toolId != definition.id || result.target.length > 2048 || result.summary.length > 4096 ||
          result.details.length > 128 || result.findings.length > 128 ||
          result.details.any((detail) => detail.length > 8192) ||
          result.findings.any((finding) => finding.title.length > 512 || finding.recommendation.length > 2048)) {
        throw const ToolOrchestrationException('Runtime returned an invalid tool result.');
      }
      await _emitActivity(activity.copyWith(
        status: ActivityStatus.completed,
        finishedAt: DateTime.now().toUtc(),
        summary: _boundedActivitySummary(result.summary),
        findingCount: result.findings.length,
        sourceResultKey: activityResultKey(result.toolId, result.target, result.completedAt),
      ));
      return result;
    } on Exception catch (error, stack) {
      final cancelled = error is RuntimeExecutionCancelled || invocation.cancellationToken?.isCancelled == true;
      await _emitActivity(activity.copyWith(
        status: cancelled ? ActivityStatus.cancelled : ActivityStatus.failed,
        finishedAt: DateTime.now().toUtc(),
        summary: cancelled ? 'Check cancelled.' : 'The check failed before producing a report.',
      ));
      if (cancelled) throw const RuntimeExecutionCancelled();
      DiagnosticReporter.recordGlobal(error, stackTrace: stack, category: DiagnosticCategory.network);
      if (error is RuntimeExecutionException) throw ToolExecutionException(error.message);
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
    RuntimeCancellationToken? cancellationToken,
    void Function(AssessmentCheckOutcome outcome)? onOutcome,
  }) async {
    final ids = toolIds.toSet().where((id) => id != 'response_analyzer').toList();
    if (ids.isEmpty) throw const ToolOrchestrationException('Select at least one technical check.');
    final startedAt = DateTime.now().toUtc();
    final outcomes = <AssessmentCheckOutcome>[];
    final results = <ToolRunResult>[];
    final assessmentActivity = ActivityEvent(
      eventId: _newActivityId('assessment'),
      kind: ActivityKind.assessment,
      target: sanitizeActivityTarget(target),
      status: ActivityStatus.started,
      startedAt: startedAt,
    );

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
          cancellationToken: cancellationToken,
          parentActivityId: assessmentActivity.eventId,
        ));
        results.add(result);
        outcome = AssessmentCheckOutcome(toolId: toolId, status: AssessmentCheckStatus.completed, result: result);
      } on Exception catch (error) {
        if (error is RuntimeExecutionCancelled || cancellationToken?.isCancelled == true) {
          outcome = AssessmentCheckOutcome(toolId: toolId, status: AssessmentCheckStatus.cancelled, error: 'Check cancelled.');
        } else {
          outcome = AssessmentCheckOutcome(toolId: toolId, status: AssessmentCheckStatus.failed, error: error.toString());
        }
      }
      outcomes.add(outcome);
      onOutcome?.call(outcome);
    }

    await _emitActivity(assessmentActivity);
    await _emitActivity(assessmentActivity.copyWith(status: ActivityStatus.running));
    try {
      for (final id in ids) {
        if (cancellationToken?.isCancelled == true) break;
        await runOne(
          id,
          checkTarget: target,
          checkAuthorized: authorized,
          allowPrivate: allowPrivateNetwork,
        );
      }
      if (includeResponseAnalysis && results.isNotEmpty && cancellationToken?.isCancelled != true) {
        await runOne(
          'response_analyzer',
          checkTarget: results.first.target,
          checkAuthorized: false,
          prior: results.toList(growable: false),
        );
      }
      final completedAt = DateTime.now().toUtc();
      final completedCount = outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.completed).length;
      final failedCount = outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.failed).length;
      final cancelledCount = outcomes.where((outcome) => outcome.status == AssessmentCheckStatus.cancelled).length;
      final cancelled = cancellationToken?.isCancelled == true || cancelledCount > 0;
      final activityStatus = cancelled ? ActivityStatus.cancelled : failedCount > 0 ? ActivityStatus.failed : ActivityStatus.completed;
      final findingCount = results.where((result) => result.toolId != 'response_analyzer').fold<int>(
        0,
        (sum, result) => sum + result.findings.length,
      ).clamp(0, 128).toInt();
      await _emitActivity(assessmentActivity.copyWith(
        status: activityStatus,
        finishedAt: completedAt,
        summary: _boundedActivitySummary('$completedCount checks completed, $failedCount failed, $cancelledCount cancelled.'),
        findingCount: findingCount,
      ));
      return AssessmentExecution(
        target: results.isEmpty ? target : results.first.target,
        startedAt: startedAt,
        completedAt: completedAt,
        outcomes: List.unmodifiable(outcomes),
      );
    } catch (error) {
      final cancelled = cancellationToken?.isCancelled == true || error is RuntimeExecutionCancelled;
      await _emitActivity(assessmentActivity.copyWith(
        status: cancelled ? ActivityStatus.cancelled : ActivityStatus.failed,
        finishedAt: DateTime.now().toUtc(),
        summary: cancelled ? 'Assessment cancelled.' : 'Assessment ended before completion.',
      ));
      rethrow;
    }
  }

}
