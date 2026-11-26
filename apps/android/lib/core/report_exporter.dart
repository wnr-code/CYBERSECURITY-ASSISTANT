import 'dart:convert';

import 'security_tools.dart';

/// Serializes explicitly selected, in-memory results for user-initiated export.
/// Consumers must show a privacy warning before copying/sharing this content.
String buildSessionReportJson(List<ToolRunResult> results, {DateTime? generatedAt}) {
  final checks = results.where((result) => result.toolId != 'response_analyzer').toList();
  final findings = checks.expand((result) => result.findings).toList();
  final report = <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': (generatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'summary': {
      'checkCount': checks.length,
      'findingCount': findings.length,
    },
    'checks': [
      for (final result in checks)
        {
          'toolId': result.toolId,
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
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(report);
}
