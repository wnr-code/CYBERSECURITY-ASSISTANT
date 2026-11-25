import 'dart:convert';

import 'tool_orchestrator.dart';

/// Builds an explicit, user-initiated export for one Assessment run. This
/// includes unsuccessful outcomes as well as result evidence so partial runs
/// are not silently presented as complete.
String buildAssessmentReportJson({
  required String target,
  required Iterable<String> selectedToolIds,
  required bool authorizationConfirmed,
  required bool privateNetworkAllowed,
  required Iterable<AssessmentCheckOutcome> outcomes,
  DateTime? generatedAt,
}) {
  final items = outcomes.toList(growable: false);
  final report = <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': (generatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'target': target,
    'authorizationConfirmed': authorizationConfirmed,
    'privateNetworkAllowed': privateNetworkAllowed,
    'selectedToolIds': selectedToolIds.toList(growable: false),
    'summary': {
      'outcomeCount': items.length,
      'completedCount': items.where((item) => item.status == AssessmentCheckStatus.completed).length,
      'failedCount': items.where((item) => item.status == AssessmentCheckStatus.failed).length,
      'skippedCount': items.where((item) => item.status == AssessmentCheckStatus.skipped).length,
      'cancelledCount': items.where((item) => item.status == AssessmentCheckStatus.cancelled).length,
    },
    'outcomes': [for (final outcome in items) _serializeOutcome(outcome)],
  };
  return const JsonEncoder.withIndent('  ').convert(report);
}

Map<String, Object?> _serializeOutcome(AssessmentCheckOutcome outcome) {
  final serialized = <String, Object?>{
    'toolId': outcome.toolId,
    'status': outcome.status.name,
    if (outcome.error != null) 'error': outcome.error,
  };
  final result = outcome.result;
  if (result != null) {
    serialized.addAll({
      'target': result.target,
      'completedAt': result.completedAt.toUtc().toIso8601String(),
      'authorizationConfirmed': result.authorizationConfirmed,
      'summary': result.summary,
      'details': result.details,
      'findings': [
        for (final finding in result.findings)
          {
            'severity': finding.severity.name,
            'confidence': finding.confidence.name,
            'title': finding.title,
            'recommendation': finding.recommendation,
            'category': finding.category,
            'description': finding.description,
            'evidence': finding.evidence,
            'riskIdentity': finding.riskIdentity,
          },
      ],
    });
  }
  return serialized;
}
