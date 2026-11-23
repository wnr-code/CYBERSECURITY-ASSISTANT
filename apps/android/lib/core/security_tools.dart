import 'dart:async';
import 'dart:io';

import 'policy_engine.dart';

enum FindingSeverity { high, medium, low, info }

class SecurityFinding {
  const SecurityFinding({required this.title, required this.severity, required this.recommendation});
  final String title;
  final FindingSeverity severity;
  final String recommendation;
}

class ToolRunResult {
  const ToolRunResult({
    required this.toolId,
    required this.target,
    required this.summary,
    required this.details,
    required this.findings,
    required this.completedAt,
    this.authorizationConfirmed = false,
  });

  final String toolId;
  final String target;
  final String summary;
  final List<String> details;
  final List<SecurityFinding> findings;
  final DateTime completedAt;
  /// Records that the in-app confirmation gate was accepted; it is not proof of authorization.
  final bool authorizationConfirmed;
}

class ToolExecutionException implements Exception {
  const ToolExecutionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Built-in, narrowly scoped P0 adapters. No shell commands or downloaded code
/// are executed. Every target is validated immediately before the network call.
class SecurityTools {
  SecurityTools({PolicyEngine? policy}) : _policy = policy ?? PolicyEngine();
  final PolicyEngine _policy;
  static const _timeout = Duration(seconds: 8);
  static const _sensitiveResponseHeaders = {
    'authorization',
    'proxy-authenticate',
    'www-authenticate',
    'set-cookie',
    'set-cookie2',
    'location',
    'content-location',
    'refresh',
  };
  static final _sensitiveHeaderNamePattern = RegExp(
    r'(^|[-_])(auth|authentication|authorization|cookie|token|secret|password|credential|api[-_]?key)([-_]|$)',
  );
  static final _sensitiveQueryParameterPattern = RegExp(
    r'([?&](?:access[_-]?token|api[_-]?key|auth(?:orization)?|code|credential|key|password|secret|session(?:id)?|token)=)[^&#\s,;]+',
    caseSensitive: false,
  );
  static final _authorizationValuePattern = RegExp(
    r'\b(?:bearer|basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final _jwtValuePattern = RegExp(r'\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b');
  static final _urlCredentialPattern = RegExp(r'\b(https?://)[^/@\s]+@', caseSensitive: false);

  static String redactResponseHeader(String name, String value) {
    final normalizedName = name.toLowerCase();
    if (_sensitiveResponseHeaders.contains(normalizedName) ||
        _sensitiveHeaderNamePattern.hasMatch(normalizedName)) {
      return '[redacted]';
    }
    return value
        .replaceAllMapped(_sensitiveQueryParameterPattern, (match) => '${match[1]}[redacted]')
        .replaceAll(_authorizationValuePattern, '[redacted]')
        .replaceAll(_jwtValuePattern, '[redacted]')
        .replaceAllMapped(_urlCredentialPattern, (match) => '${match[1]}[redacted]@');
  }

  Future<ToolRunResult> runDnsLookup(String input, {required bool authorized}) async {
    final target = _policy.validateTarget(input, authorized: authorized);
    try {
      final addresses = await InternetAddress.lookup(target.host).timeout(_timeout);
      final unique = addresses.map((address) => address.address).toSet().toList()..sort();
      if (unique.isEmpty) throw const ToolExecutionException('The device resolver returned no addresses.');
      return ToolRunResult(
        toolId: 'dns_lookup',
        target: target.host,
        summary: 'Resolved ${unique.length} address${unique.length == 1 ? '' : 'es'}.',
        details: unique,
        findings: const [],
        completedAt: DateTime.now().toUtc(),
        authorizationConfirmed: true,
      );
    } on SocketException catch (error) {
      throw ToolExecutionException('DNS lookup failed: ${_safeError(error.message)}');
    } on TimeoutException {
      throw const ToolExecutionException('DNS lookup timed out after 8 seconds.');
    }
  }

  Future<ToolRunResult> inspectTls(String input, {required bool authorized}) async {
    final target = _policy.validateTarget(input, authorized: authorized);
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(target.host, 443, timeout: _timeout);
      final certificate = socket.peerCertificate;
      if (certificate == null) throw const ToolExecutionException('The server did not present a peer certificate.');
      final now = DateTime.now().toUtc();
      final expires = certificate.endValidity.toUtc();
      final daysRemaining = expires.difference(now).inDays;
      final findings = <SecurityFinding>[];
      if (daysRemaining < 30) {
        findings.add(SecurityFinding(
          title: 'Certificate expires in $daysRemaining day(s)',
          severity: FindingSeverity.medium,
          recommendation: 'Renew the certificate before it expires.',
        ));
      }
      return ToolRunResult(
        toolId: 'tls_inspector',
        target: target.host,
        summary: 'TLS handshake succeeded; certificate expires ${expires.toIso8601String()}.',
        details: [
          'Subject: ${certificate.subject}',
          'Issuer: ${certificate.issuer}',
          'Valid from: ${certificate.startValidity.toUtc().toIso8601String()}',
          'Valid until: ${expires.toIso8601String()}',
          'Days remaining: $daysRemaining',
          'Trust validation: passed by the device TLS stack',
        ],
        findings: findings,
        completedAt: DateTime.now().toUtc(),
        authorizationConfirmed: true,
      );
    } on HandshakeException {
      throw const ToolExecutionException('TLS handshake or certificate validation failed.');
    } on SocketException catch (error) {
      throw ToolExecutionException('Could not connect to HTTPS service: ${_safeError(error.message)}');
    } on TimeoutException {
      throw const ToolExecutionException('TLS inspection timed out after 8 seconds.');
    } finally {
      socket?.destroy();
    }
  }

  Future<ToolRunResult> checkHttpHeaders(String input, {required bool authorized}) async {
    final target = _policy.validateTarget(input, authorized: authorized);
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(target.uri).timeout(_timeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(_timeout);
      final statusCode = response.statusCode;
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(', ');
      });
      // Cancel rather than download an unneeded, potentially large response body.
      await response.listen((_) {}).cancel();

      final findings = <SecurityFinding>[];
      _missingHeader(findings, headers, 'strict-transport-security', 'HTTP Strict Transport Security (HSTS)',
          'Configure HSTS after confirming all subdomains support HTTPS.');
      _missingHeader(findings, headers, 'content-security-policy', 'Content Security Policy (CSP)',
          'Define a restrictive CSP appropriate to the site.');
      _missingHeader(findings, headers, 'x-content-type-options', 'X-Content-Type-Options',
          'Set X-Content-Type-Options: nosniff.');
      _missingHeader(findings, headers, 'referrer-policy', 'Referrer-Policy',
          'Set a policy such as strict-origin-when-cross-origin.');
      _missingHeader(findings, headers, 'permissions-policy', 'Permissions-Policy',
          'Disable browser features the site does not need.');
      if (headers.containsKey('server') || headers.containsKey('x-powered-by')) {
        findings.add(const SecurityFinding(
          title: 'Server technology header is exposed',
          severity: FindingSeverity.info,
          recommendation: 'Consider minimizing unnecessary implementation details in response headers.',
        ));
      }
      return ToolRunResult(
        toolId: 'http_headers',
        target: target.host,
        summary: 'Received HTTP $statusCode and inspected ${headers.length} response headers.',
        details: [
          for (final entry in headers.entries)
            '${entry.key}: ${redactResponseHeader(entry.key, entry.value)}',
          if (headers.isEmpty) 'The response contained no headers.',
          if (statusCode >= 300 && statusCode < 400) 'Redirect returned; it was not followed.',
        ],
        findings: findings,
        completedAt: DateTime.now().toUtc(),
        authorizationConfirmed: true,
      );
    } on HandshakeException {
      throw const ToolExecutionException('TLS handshake or certificate validation failed.');
    } on SocketException catch (error) {
      throw ToolExecutionException('Could not reach HTTPS service: ${_safeError(error.message)}');
    } on TimeoutException {
      throw const ToolExecutionException('HTTP header check timed out after 8 seconds.');
    } on HttpException {
      throw const ToolExecutionException('The HTTPS request failed.');
    } finally {
      client.close(force: true);
    }
  }

  ToolRunResult analyze(List<ToolRunResult> results, {required String target}) {
    final findings = results.expand((result) => result.findings).toList();
    final severityOrder = <FindingSeverity, int>{
      FindingSeverity.high: 0,
      FindingSeverity.medium: 1,
      FindingSeverity.low: 2,
      FindingSeverity.info: 3,
    };
    findings.sort((a, b) => severityOrder[a.severity]!.compareTo(severityOrder[b.severity]!));
    final summary = findings.isEmpty
        ? 'No findings were produced by the completed checks.'
        : '${findings.length} finding${findings.length == 1 ? '' : 's'} across ${results.length} check(s).';
    return ToolRunResult(
      toolId: 'response_analyzer',
      target: target,
      summary: summary,
      details: [for (final result in results) '${result.toolId}: ${result.summary}'],
      findings: findings,
      completedAt: DateTime.now().toUtc(),
    );
  }

  void _missingHeader(List<SecurityFinding> findings, Map<String, String> headers, String key, String name, String recommendation) {
    if (!headers.containsKey(key)) {
      findings.add(SecurityFinding(
        title: '$name header not observed',
        severity: FindingSeverity.low,
        recommendation: recommendation,
      ));
    }
  }

  String _safeError(String message) {
    final singleLine = message.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return singleLine.length > 160 ? '${singleLine.substring(0, 160)}…' : singleLine;
  }
}
