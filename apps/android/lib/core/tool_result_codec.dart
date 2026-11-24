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
            'confidence': finding.confidence.name,
            'recommendation': finding.recommendation,
            'category': finding.category,
            'description': finding.description,
            'evidence': finding.evidence,
            'riskIdentity': finding.riskIdentity,
          },
      ],
      'completedAt': result.completedAt.toUtc().toIso8601String(),
      'authorizationConfirmed': result.authorizationConfirmed,
      if (result.assessmentId != null) 'assessmentId': result.assessmentId,
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
  final rawAssessmentId = decoded['assessmentId'];
  if (rawAssessmentId != null && (rawAssessmentId is! String || rawAssessmentId.length > 128)) {
    throw const FormatException('Stored assessment linkage is invalid.');
  }
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
    final confidenceName = rawFinding['confidence'];
    final recommendation = rawFinding['recommendation'];
    final category = rawFinding['category'];
    final description = rawFinding['description'];
    final rawEvidence = rawFinding['evidence'];
    final riskIdentity = rawFinding['riskIdentity'];
    if (title is! String || severityName is! String || recommendation is! String ||
        (confidenceName != null && confidenceName is! String) ||
        (category != null && category is! String) ||
        (description != null && description is! String) ||
        (riskIdentity != null && riskIdentity is! String) ||
        (rawEvidence != null && (rawEvidence is! List || rawEvidence.any((value) => value is! String)))) {
      throw const FormatException('Stored finding is missing required fields.');
    }
    FindingSeverity? severity;
    for (final candidate in FindingSeverity.values) {
      if (candidate.name == severityName) severity = candidate;
    }
    if (severity == null) throw FormatException('Unknown finding severity "$severityName".');
    FindingConfidence? confidence;
    if (confidenceName is String) {
      for (final candidate in FindingConfidence.values) {
        if (candidate.name == confidenceName) confidence = candidate;
      }
      if (confidence == null) throw FormatException('Unknown finding confidence "$confidenceName".');
    } else if (severity == FindingSeverity.info) {
      // Backward compatibility for saved reports created before confidence labels.
      confidence = FindingConfidence.informational;
    }
    findings.add(SecurityFinding(
      title: title,
      severity: severity,
      confidence: confidence ?? FindingConfidence.potential,
      recommendation: recommendation,
      category: category as String? ?? 'General',
      description: description as String? ?? '',
      evidence: (rawEvidence as List?)?.cast<String>() ?? const [],
      riskIdentity: riskIdentity as String?,
    ));
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
    assessmentId: rawAssessmentId as String?,
  );
}
