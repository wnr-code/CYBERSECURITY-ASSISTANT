import 'dart:convert';

import 'package:cybersecurity_assistant/core/github_releases.dart';
import 'package:cybersecurity_assistant/core/policy_engine.dart';
import 'package:cybersecurity_assistant/core/provider_registry.dart';
import 'package:cybersecurity_assistant/core/report_exporter.dart';
import 'package:cybersecurity_assistant/core/security_tools.dart';
import 'package:cybersecurity_assistant/core/tool_orchestrator.dart';
import 'package:cybersecurity_assistant/core/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('rejects HTTP, query strings, custom ports, and non-root paths', () {
      for (final input in [
        'http://example.com',
        'https://example.com/?token=secret',
        'https://example.com:8443',
        'https://example.com:not-a-port',
        'https://example.com/admin',
      ]) {
        expect(
          () => policy.validateTarget(input, authorized: true),
          throwsA(isA<PolicyException>()),
          reason: 'Should reject $input',
        );
      }
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
