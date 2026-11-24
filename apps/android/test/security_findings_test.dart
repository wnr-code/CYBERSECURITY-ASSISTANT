import 'package:cybersecurity_assistant/core/security_findings.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:flutter_test/flutter_test.dart';

FindingRecord _observed({
  required DateTime at,
  String target = 'https://example.com/private?token=must-not-persist',
  String title = 'Missing security header',
  String category = 'HTTP Security Headers',
  String evidence = 'content-security-policy was not observed',
  String riskIdentity = 'missing-csp',
  FindingSeverity severity = FindingSeverity.low,
  FindingConfidence confidence = FindingConfidence.potential,
  String reportKey = 'a' * 64,
  String? assessmentId,
}) => findingRecordFromTool(
      finding: SecurityFinding(
        title: title,
        severity: severity,
        confidence: confidence,
        category: category,
        description: 'The check observed a potential indicator.',
        evidence: [evidence],
        riskIdentity: riskIdentity,
        recommendation: 'Review the header configuration.',
      ),
      result: ToolRunResult(
        toolId: 'http_headers',
        target: target,
        summary: 'HTTP fixture completed.',
        details: const [],
        findings: const [],
        completedAt: at,
        authorizationConfirmed: true,
      ),
      sourceReportKey: reportKey,
      assessmentId: assessmentId,
    );

void main() {
  test('deduplicates the same indicator across assessments and preserves first seen and user status', () async {
    final repository = MemoryFindingRepository();
    final firstSeen = DateTime.utc(2026, 10, 1);
    final secondSeen = DateTime.utc(2026, 11, 1);
    final first = _observed(at: firstSeen, reportKey: '1' * 64, assessmentId: 'assessment-1');
    final second = _observed(at: secondSeen, reportKey: '2' * 64, assessmentId: 'assessment-2');

    final initial = (await repository.saveObservedFindings([first])).single;
    await repository.updateFindingStatus(initial.findingId, FindingStatus.inProgress);
    final observedAgain = (await repository.saveObservedFindings([second])).single;
    final all = await repository.loadFindings();

    expect(all, hasLength(1));
    expect(observedAgain.findingId, initial.findingId);
    expect(observedAgain.fingerprint, initial.fingerprint);
    expect(observedAgain.firstSeen, firstSeen);
    expect(observedAgain.lastSeen, secondSeen);
    expect(observedAgain.createdAt, firstSeen);
    expect(observedAgain.status, FindingStatus.inProgress);
    expect(observedAgain.assessmentId, 'assessment-2');
    expect(observedAgain.sourceReportKeys.toSet(), {'1' * 64, '2' * 64});
  });

  test('does not collapse distinct risk identities that share a title', () async {
    final repository = MemoryFindingRepository();
    final observedAt = DateTime.utc(2026);
    await repository.saveObservedFindings([
      _observed(at: observedAt, riskIdentity: 'missing-csp', evidence: 'CSP absent'),
      _observed(at: observedAt, riskIdentity: 'missing-hsts', evidence: 'HSTS absent'),
      _observed(at: observedAt, riskIdentity: 'missing-csp', evidence: 'CSP policy invalid'),
    ]);

    final findings = await repository.loadFindings();
    expect(findings, hasLength(3));
    expect(findings.map((finding) => finding.fingerprint).toSet(), hasLength(3));
  });

  test('supports explicit false-positive and other user-reviewed lifecycle statuses', () async {
    final repository = MemoryFindingRepository();
    final record = (await repository.saveObservedFindings([_observed(at: DateTime.utc(2026))])).single;

    final falsePositive = await repository.updateFindingStatus(record.findingId, FindingStatus.falsePositive);
    expect(falsePositive.status, FindingStatus.falsePositive);
    expect((await repository.loadFindings(status: FindingStatus.falsePositive)).single.findingId, record.findingId);
    expect((await repository.updateFindingStatus(record.findingId, FindingStatus.accepted)).status, FindingStatus.accepted);
    expect((await repository.updateFindingStatus(record.findingId, FindingStatus.resolved)).status, FindingStatus.resolved);
  });

  test('filters severity, status, category, target and full-text search independently', () async {
    final repository = MemoryFindingRepository();
    final now = DateTime.utc(2026);
    await repository.saveObservedFindings([
      _observed(at: now, target: 'alpha.example', category: 'HTTP Headers', title: 'CSP absent', riskIdentity: 'alpha-csp'),
      _observed(at: now.add(const Duration(seconds: 1)), target: 'beta.example', category: 'TLS Certificate', title: 'Certificate expiry', evidence: 'expires soon', riskIdentity: 'beta-expiry', severity: FindingSeverity.medium),
    ]);
    final all = await repository.loadFindings();
    await repository.updateFindingStatus(all.first.findingId, FindingStatus.falsePositive);

    expect((await repository.loadFindings(severity: FindingSeverity.medium)), hasLength(1));
    expect((await repository.loadFindings(status: FindingStatus.falsePositive)), hasLength(1));
    expect((await repository.loadFindings(category: 'tls')), hasLength(1));
    expect((await repository.loadFindings(target: 'ALPHA')), hasLength(1));
    expect((await repository.loadFindings(query: 'expires soon')), hasLength(1));
  });

  test('sanitizes target and all persisted text, retaining only bounded redacted evidence', () async {
    final repository = MemoryFindingRepository();
    final source = _observed(
      at: DateTime.utc(2026),
      target: 'https://alice:password@example.com/private?access_token=hidden',
      evidence: 'https://bob:secret@example.com/path?token=topsecret Bearer abc.def.ghi',
      reportKey: 'f' * 64,
    );
    final saved = (await repository.saveObservedFindings([source])).single;

    expect(saved.target, 'example.com');
    expect(saved.evidence.join(' '), isNot(contains('alice')));
    expect(saved.evidence.join(' '), isNot(contains('password')));
    expect(saved.evidence.join(' '), isNot(contains('topsecret')));
    expect(saved.evidence.join(' '), isNot(contains('abc.def.ghi')));
    expect(saved.sourceReportKeys, ['f' * 64]);
    expect(saved.description, isNot(contains('token')));
  });

  test('error confidence stays distinct from severity and tool errors are not represented by this model', () {
    final errorClassified = _observed(
      at: DateTime.utc(2026),
      confidence: FindingConfidence.error,
    );
    expect(errorClassified.confidence, FindingConfidence.error);
    expect(errorClassified.severity, FindingSeverity.low);
  });
}
