import 'dart:convert';

import 'security_tools.dart';

String encodeToolRunResult(ToolRunResult result) => jsonEncode({
      'toolId': result.toolId,
      'target': result.target,
      'summary': result.summary,
      'details': result.details,
      'findings': [
        for (final finding in result.findings)
          {
            'title': finding.title,
            'severity': finding.severity.name,
            'recommendation': finding.recommendation,
          },
      ],
      'completedAt': result.completedAt.toUtc().toIso8601String(),
      'authorizationConfirmed': result.authorizationConfirmed,
    });

ToolRunResult decodeToolRunResult(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Stored tool result must be a JSON object.');
  }

  String requiredString(String key) {
    final value = decoded[key];
    if (value is! String) throw FormatException('Stored tool result field "$key" is invalid.');
    return value;
  }

  final rawDetails = decoded['details'];
  final rawFindings = decoded['findings'];
  final rawAuthorization = decoded['authorizationConfirmed'];
  if (rawDetails is! List || rawDetails.any((value) => value is! String)) {
    throw const FormatException('Stored tool result details are invalid.');
  }
  if (rawFindings is! List || rawAuthorization is! bool) {
    throw const FormatException('Stored tool result findings or authorization marker are invalid.');
  }

  final findings = <SecurityFinding>[];
  for (final rawFinding in rawFindings) {
    if (rawFinding is! Map<String, dynamic>) {
      throw const FormatException('Stored finding has an invalid format.');
    }
    final title = rawFinding['title'];
    final severityName = rawFinding['severity'];
    final recommendation = rawFinding['recommendation'];
    if (title is! String || severityName is! String || recommendation is! String) {
      throw const FormatException('Stored finding is missing required fields.');
    }
    FindingSeverity? severity;
    for (final candidate in FindingSeverity.values) {
      if (candidate.name == severityName) severity = candidate;
    }
    if (severity == null) throw FormatException('Unknown finding severity "$severityName".');
    findings.add(SecurityFinding(title: title, severity: severity, recommendation: recommendation));
  }

  final completedAt = DateTime.tryParse(requiredString('completedAt'));
  if (completedAt == null) throw const FormatException('Stored result timestamp is invalid.');
  return ToolRunResult(
    toolId: requiredString('toolId'),
    target: requiredString('target'),
    summary: requiredString('summary'),
    details: rawDetails.cast<String>(),
    findings: findings,
    completedAt: completedAt.toUtc(),
    authorizationConfirmed: rawAuthorization,
  );
}
