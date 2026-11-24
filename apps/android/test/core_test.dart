import 'dart:convert';

import 'package:cybersecurity_assistant/core/github_releases.dart';
import 'package:cybersecurity_assistant/core/policy_engine.dart';
import 'package:cybersecurity_assistant/core/provider_registry.dart';
import 'package:cybersecurity_assistant/core/report_exporter.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/tool_orchestrator.dart';
import 'package:cybersecurity_assistant/core/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedSecurityTools extends SecurityTools {
  @override
  Future<ToolRunResult> runDnsLookup(String input, {required bool authorized}) async => ToolRunResult(
        toolId: 'dns_lookup',
        target: 'example.com',
        summary: 'DNS fixture completed.',
        details: const ['A records: 192.0.2.1'],
        findings: const [],
        completedAt: DateTime.utc(2026, 11, 23),
        authorizationConfirmed: authorized,
      );

  @override
  Future<ToolRunResult> inspectTls(String input, {required bool authorized}) async {
    throw const ToolExecutionException('TLS fixture failed.');
  }

  @override
  Future<ToolRunResult> checkHttpHeaders(String input, {required bool authorized}) async => ToolRunResult(
        toolId: 'http_headers',
        target: 'example.com',
        summary: 'HTTP fixture completed.',
        details: const ['HTTP 200 fixture'],
        findings: const [
          SecurityFinding(
            title: 'Fixture finding',
            severity: FindingSeverity.low,
            recommendation: 'Review the fixture.',
          ),
        ],
        completedAt: DateTime.utc(2026, 11, 23),
        authorizationConfirmed: authorized,
      );
}

void main() {
  group('PolicyEngine', () {
    final policy = PolicyEngine();

    test('requires explicit authorization before accepting a target', () {
      expect(
        () => policy.validateTarget('example.com', authorized: false),
        throwsA(isA<PolicyException>()),
      );
    });

    test('normalizes a bare hostname to an HTTPS origin', () {
      final target = policy.validateTarget('Example.COM', authorized: true);
      expect(target.host, 'example.com');
      expect(target.uri.toString(), 'https://example.com/');
    });

    test('rejects HTTP, query strings, and nonstandard ports', () {
      for (final input in [
        'http://example.com',
        'https://example.com/?token=secret',
        'https://example.com:8443',
        'https://example.com:not-a-port',
      ]) {
        expect(
          () => policy.validateTarget(input, authorized: true),
          throwsA(isA<PolicyException>()),
          reason: 'Should reject $input',
        );
      }
    });

    test('accepts an authorized HTTPS API path without query parameters', () {
      final target = policy.validateTarget(
        'https://quran.cgs.my.id/api/quran/surat',
        authorized: true,
      );
      expect(target.host, 'quran.cgs.my.id');
      expect(target.uri.toString(), 'https://quran.cgs.my.id/api/quran/surat');
      expect(target.scope, 'quran.cgs.my.id/api/quran/surat');
    });

    test('accepts valid IPv4 targets and rejects malformed numeric addresses', () {
      final ipv4 = policy.validateTarget('192.0.2.15', authorized: true);
      expect(ipv4.host, '192.0.2.15');
      expect(ipv4.uri.host, '192.0.2.15');
      for (final invalid in ['999.999.999.999', '192.168.01.1', '192.168.1']) {
        expect(
          () => policy.validateTarget(invalid, authorized: true),
          throwsA(isA<PolicyException>()),
          reason: 'Should reject malformed IPv4 target $invalid',
        );
      }
    });

    test('rejects embedded credentials and fragments', () {
      for (final input in [
        'https://user:password@example.com',
        'https://example.com/#fragment',
      ]) {
        expect(
          () => policy.validateTarget(input, authorized: true),
          throwsA(isA<PolicyException>()),
        );
      }
    });
  });

  group('Tool Registry', () {
    test('has unique IDs and adapters for the P0 set', () {
      expect(toolRegistry.map((tool) => tool.id).toSet().length, toolRegistry.length);
      expect(toolRegistry, hasLength(4));
      expect(toolRegistry.every((tool) => tool.status == ToolStatus.available), isTrue);
      expect(toolById('dns_lookup')?.name, 'DNS Lookup');
      expect(toolById('http_headers')?.requiredPermissions, contains('INTERNET'));
      expect(toolById('response_analyzer')?.requiredPermissions, isEmpty);
      expect(toolById('missing'), isNull);
      expect(ToolCategory.values, containsAll([
        ToolCategory.osint,
        ToolCategory.apkMobileSecurity,
        ToolCategory.codeSecurity,
        ToolCategory.cloudSecurity,
        ToolCategory.vulnerabilityAssessment,
        ToolCategory.malwareAnalysis,
        ToolCategory.threatIntelligence,
      ]));
    });
  });

  group('Provider Registry', () {
    test('catalogue IDs are unique and no provider claims an implemented connector', () {
      expect(providerRegistry, isNotEmpty);
      expect(providerRegistry.map((provider) => provider.id).toSet().length, providerRegistry.length);
      expect(providerRegistry.every((provider) => !provider.integrationImplemented), isTrue);
      expect(providerRegistry.any((provider) => provider.category == ProviderCategory.ai), isTrue);
      expect(providerAuthLabel(ProviderAuthType.apiKey), 'User-owned API key required');
    });
  });

  group('Tool Orchestrator', () {
    final orchestrator = ToolOrchestrator();

    test('rejects unregistered and shell-like tool IDs without executing them', () async {
      await expectLater(
        orchestrator.execute(const ToolInvocation(
          toolId: 'sh -c echo unsafe',
          target: '',
          authorized: true,
        )),
        throwsA(isA<ToolOrchestrationException>()),
      );
    });

    test('does not dispatch a network adapter without explicit authorization', () async {
      await expectLater(
        orchestrator.execute(const ToolInvocation(
          toolId: 'dns_lookup',
          target: 'example.com',
          authorized: false,
        )),
        throwsA(isA<PolicyException>()),
      );
    });

    test('requires saved local results for analysis', () async {
      await expectLater(
        orchestrator.execute(const ToolInvocation(
          toolId: 'response_analyzer',
          target: '',
          authorized: false,
        )),
        throwsA(isA<ToolOrchestrationException>()),
      );
    });

    test('keeps local analysis scoped to the requested target', () async {
      final now = DateTime.utc(2026, 11, 23);
      final first = ToolRunResult(
        toolId: 'http_headers',
        target: 'example.com',
        summary: 'first target',
        details: const [],
        findings: const [],
        completedAt: now,
      );
      final second = ToolRunResult(
        toolId: 'http_headers',
        target: 'other.example',
        summary: 'other target',
        details: const [],
        findings: const [],
        completedAt: now,
      );

      final result = await orchestrator.execute(ToolInvocation(
        toolId: 'response_analyzer',
        target: 'example.com',
        authorized: false,
        priorResults: [first, second],
      ));
      expect(result.target, 'example.com');
      expect(result.details, ['http_headers: first target']);
    });
  });

  group('Multi-check assessments', () {
    test('runs selected tools sequentially and preserves failures alongside completed evidence', () async {
      final orchestrator = ToolOrchestrator(tools: _ScriptedSecurityTools());
      final callbacks = <AssessmentCheckOutcome>[];
      final assessment = await orchestrator.runAssessment(
        target: 'https://example.com',
        toolIds: const ['dns_lookup', 'tls_inspector', 'http_headers'],
        authorized: true,
        onOutcome: callbacks.add,
      );

      expect(assessment.outcomes.map((outcome) => outcome.status), [
        AssessmentCheckStatus.completed,
        AssessmentCheckStatus.failed,
        AssessmentCheckStatus.completed,
        AssessmentCheckStatus.completed,
      ]);
      expect(assessment.outcomes.map((outcome) => outcome.toolId), [
        'dns_lookup',
        'tls_inspector',
        'http_headers',
        'response_analyzer',
      ]);
      expect(assessment.completedCount, 3);
      expect(assessment.failedCount, 1);
      expect(assessment.outcomes[1].error, contains('TLS fixture failed'));
      expect(assessment.outcomes.last.result?.findings.single.title, 'Fixture finding');
      expect(callbacks, hasLength(4));
    });

    test('requires at least one technical check', () async {
      await expectLater(
        ToolOrchestrator(tools: _ScriptedSecurityTools()).runAssessment(
          target: 'example.com',
          toolIds: const [],
          authorized: true,
        ),
        throwsA(isA<ToolOrchestrationException>()),
      );
    });
  });

  group('GitHub release metadata', () {
    final repository = githubReferenceRepositories.first;
    final client = GitHubReleaseClient();

    test('parses allowlisted release metadata and an optional SHA-256 digest', () {
      final digest = 'a' * 64;
      final body = jsonEncode({
        'tag_name': 'v1.2.3',
        'name': 'Reference release',
        'html_url': 'https://github.com/${repository.fullName}/releases/tag/v1.2.3',
        'published_at': '2026-11-23T00:00:00Z',
        'assets': [
          {
            'name': 'reference.zip',
            'size': 1024,
            'content_type': 'application/zip',
            'browser_download_url': 'https://github.com/${repository.fullName}/releases/download/v1.2.3/reference.zip',
            'digest': 'sha256:$digest',
          },
        ],
      });

      final release = client.parseLatestRelease(body, repository);
      expect(release.tag, 'v1.2.3');
      expect(release.assets, hasLength(1));
      expect(release.assets.single.sha256, digest);
      expect(release.assets.single.sizeBytes, 1024);
    });

    test('rejects release and asset URLs outside the allowlisted repository', () {
      final invalidRelease = jsonEncode({
        'tag_name': 'v1',
        'name': 'Bad URL',
        'html_url': 'https://attacker.example/releases/tag/v1',
        'assets': [],
      });
      expect(
        () => client.parseLatestRelease(invalidRelease, repository),
        throwsA(isA<GitHubReleaseException>()),
      );

      final invalidAsset = jsonEncode({
        'tag_name': 'v1',
        'name': 'Bad asset URL',
        'html_url': 'https://github.com/${repository.fullName}/releases/tag/v1',
        'assets': [
          {
            'name': 'payload.zip',
            'size': 100,
            'browser_download_url': 'https://evil.example/payload.zip',
          },
        ],
      });
      expect(
        () => client.parseLatestRelease(invalidAsset, repository),
        throwsA(isA<GitHubReleaseException>()),
      );
    });

    test('rejects repositories outside the reference allowlist before networking', () async {
      const unknown = GitHubRepository(owner: 'example', name: 'repo', description: 'not trusted');
      await expectLater(client.fetchLatest(unknown), throwsA(isA<GitHubReleaseException>()));
    });
  });

  group('Session report exporter', () {
    test('produces valid JSON and excludes duplicate analyzer rollups', () {
      final now = DateTime.utc(2026, 11, 23);
      final check = ToolRunResult(
        toolId: 'http_headers',
        target: 'example.com',
        summary: 'Received HTTP 200.',
        details: const ['set-cookie: [redacted]'],
        findings: const [
          SecurityFinding(
            title: 'CSP header not observed',
            severity: FindingSeverity.low,
            recommendation: 'Review CSP.',
          ),
        ],
        completedAt: now,
        authorizationConfirmed: true,
      );
      final rollup = SecurityTools().analyze([check], target: 'example.com');
      final decoded = jsonDecode(buildSessionReportJson([check, rollup], generatedAt: now))
          as Map<String, dynamic>;

      expect(decoded['schemaVersion'], 1);
      expect(decoded['generatedAt'], now.toIso8601String());
      expect(decoded['summary'], {'checkCount': 1, 'findingCount': 1});
      expect((decoded['checks'] as List), hasLength(1));
      expect((decoded['checks'] as List).single['authorizationConfirmed'], isTrue);
      expect((decoded['checks'] as List).single['details'], ['set-cookie: [redacted]']);
    });
  });

  group('Sensitive response-header redaction', () {
    test('redacts common secret-bearing response headers and preserves ordinary metadata', () {
      for (final name in [
        'set-cookie',
        'authorization',
        'x-api-key',
        'X-API-Key',
        'x-auth-token',
        'x-session-token',
        'x-client-secret',
      ]) {
        expect(SecurityTools.redactResponseHeader(name, 'should-not-be-exported'), '[redacted]', reason: name);
      }
      expect(SecurityTools.redactResponseHeader('content-type', 'application/json'), 'application/json');
      expect(
        SecurityTools.redactResponseHeader('x-redirect-info', 'https://example.test/?access_token=secret&view=ok'),
        'https://example.test/?access_token=[redacted]&view=ok',
      );
      expect(SecurityTools.redactResponseHeader('x-auth-info', 'Bearer token-value'), '[redacted]');
      expect(
        SecurityTools.redactResponseHeader(
          'x-session',
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature',
        ),
        '[redacted]',
      );
      expect(
        SecurityTools.redactResponseHeader('x-url', 'https://user:pass@example.test/path'),
        'https://[redacted]@example.test/path',
      );
      expect(SecurityTools.redactResponseHeader('location', 'https://example.test/path'), '[redacted]');
    });
  });

  group('API response inspection', () {
    test('finds sensitive JSON field names without retaining response values', () {
      const secret = 'private-token-value-should-never-be-retained';
      final analysis = SecurityTools.analyzeApiResponse(
        body: utf8.encode('{"data":{"access_token":"$secret","surah":"Al-Fatihah"}}'),
        contentType: 'application/json; charset=utf-8',
        truncated: false,
      );

      expect(analysis.findings, hasLength(1));
      expect(analysis.findings.single.title, contains(r'$.data.access_token'));
      expect(analysis.findings.single.severity, FindingSeverity.low);
      expect(analysis.evidence.join(' '), contains('value redacted'));
      expect(analysis.evidence.join(' '), isNot(contains(secret)));
      expect(analysis.evidence.join(' '), isNot(contains('Al-Fatihah')));
    });

    test('detects server error disclosure and marks response-size truncation', () {
      final analysis = SecurityTools.analyzeApiResponse(
        body: utf8.encode('Traceback (most recent call last):\n  File "/srv/private.py"'),
        contentType: 'text/plain',
        truncated: true,
      );

      expect(analysis.findings, hasLength(1));
      expect(analysis.findings.single.title, contains('Detailed server error'));
      expect(analysis.evidence.join(' '), contains('raw text was not retained'));
      expect(analysis.evidence.join(' '), contains('truncated'));
      expect(analysis.evidence.join(' '), isNot(contains('/srv/private.py')));
    });

    test('flags malformed JSON only when the server declares a JSON content type', () {
      final declaredJson = SecurityTools.analyzeApiResponse(
        body: utf8.encode('{bad json'),
        contentType: 'application/json',
        truncated: false,
      );
      final plainText = SecurityTools.analyzeApiResponse(
        body: utf8.encode('{bad json'),
        contentType: 'text/plain',
        truncated: false,
      );

      expect(declaredJson.findings.single.title, contains('did not parse as JSON'));
      expect(plainText.findings, isEmpty);
      expect(declaredJson.evidence.join(' '), isNot(contains('{bad json')));
    });
  });

  group('Response Analyzer', () {
    test('sorts findings by severity and preserves the result summary', () {
      final now = DateTime.utc(2026, 1, 1);
      final input = [
        ToolRunResult(
          toolId: 'http_headers',
          target: 'example.com',
          summary: 'header check',
          details: const [],
          findings: const [
            SecurityFinding(title: 'Informational', severity: FindingSeverity.info, recommendation: 'Review.'),
            SecurityFinding(title: 'High risk', severity: FindingSeverity.high, recommendation: 'Fix.'),
            SecurityFinding(title: 'Low risk', severity: FindingSeverity.low, recommendation: 'Consider.'),
          ],
          completedAt: now,
        ),
      ];

      final result = SecurityTools().analyze(input, target: 'example.com');
      expect(result.summary, '3 findings across 1 check(s).');
      expect(result.findings.map((finding) => finding.title), ['High risk', 'Low risk', 'Informational']);
      expect(result.details, ['http_headers: header check']);
    });
  });
}
