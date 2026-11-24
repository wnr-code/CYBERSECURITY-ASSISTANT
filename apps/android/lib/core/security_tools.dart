import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'policy_engine.dart';

enum FindingSeverity { high, medium, low, info }

class SecurityFinding {
  const SecurityFinding({required this.title, required this.severity, required this.recommendation});
  final String title;
  final FindingSeverity severity;
  final String recommendation;
}

class ApiResponseAnalysis {
  const ApiResponseAnalysis({required this.findings, required this.evidence});
  final List<SecurityFinding> findings;
  /// Safe, bounded evidence only. Raw response bytes and field values are never returned.
  final List<String> evidence;
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
class _BodyCapture {
  const _BodyCapture(this.bytes, this.truncated);
  final Uint8List bytes;
  final bool truncated;
}

class SecurityTools {
  SecurityTools({PolicyEngine? policy}) : _policy = policy ?? PolicyEngine();
  final PolicyEngine _policy;
  static const _timeout = Duration(seconds: 8);
  static const maxApiResponseBytes = 32 * 1024;
  static final _sensitiveJsonKeyPattern = RegExp(
    r'(?:password|passwd|secret|token|api[_-]?key|access[_-]?key|credential|private[_-]?key)',
    caseSensitive: false,
  );
  static final _serverErrorDisclosurePattern = RegExp(
    r'(?:traceback \(most recent call last\)|exception in thread|stack trace|sqlstate\[[0-9a-z]+\]| at [\w.$]+\([^\n]*:\d+\)|\b(?:syntax|query) error at or near )',
    caseSensitive: false,
  );
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
      final ipv4 = addresses
          .where((address) => address.type == InternetAddressType.IPv4)
          .map((address) => address.address)
          .toSet()
          .toList()
        ..sort();
      final ipv6 = addresses
          .where((address) => address.type == InternetAddressType.IPv6)
          .map((address) => address.address)
          .toSet()
          .toList()
        ..sort();
      final unique = {...ipv4, ...ipv6}.toList()..sort();
      if (unique.isEmpty) throw const ToolExecutionException('The device resolver returned no addresses.');
      return ToolRunResult(
        toolId: 'dns_lookup',
        target: target.scope,
        summary: 'Resolved ${unique.length} address${unique.length == 1 ? '' : 'es'}.',
        details: [
          'A records: ${ipv4.isEmpty ? 'none returned' : ipv4.join(', ')}',
          'AAAA records: ${ipv6.isEmpty ? 'none returned' : ipv6.join(', ')}',
          'Resolver: Android device system resolver.',
          'Record-type limitation: CNAME, MX, TXT, NS, and SOA are not exposed by the system hostname lookup used here.',
        ],
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
        target: target.scope,
        summary: 'TLS handshake succeeded; certificate expires ${expires.toIso8601String()}.',
        details: [
          'Requested hostname: ${target.host}',
          'Hostname and trust validation: passed by the platform TLS handshake for ${target.host}.',
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
      request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain;q=0.9, */*;q=0.5');
      final response = await request.close().timeout(_timeout);
      final statusCode = response.statusCode;
      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(', ');
      });
      final bodyCapture = await _readBoundedBody(response);
      final contentType = headers[HttpHeaders.contentTypeHeader];
      final bodyAnalysis = analyzeApiResponse(
        body: bodyCapture.bytes,
        contentType: contentType,
        truncated: bodyCapture.truncated,
      );

      final findings = <SecurityFinding>[...bodyAnalysis.findings];
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
        target: target.scope,
        summary: 'Received HTTP $statusCode and inspected ${headers.length} response headers.',
        details: [
          'Request: GET ${target.uri.path} (redirects not followed).',
          'Response body: ${bodyCapture.bytes.length} byte(s) inspected${bodyCapture.truncated ? ' (truncated at ${maxApiResponseBytes} bytes)' : ''}.',
          'Content-Type: ${contentType == null ? 'not provided' : redactResponseHeader(HttpHeaders.contentTypeHeader, contentType)}',
          ...bodyAnalysis.evidence,
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

  static Future<_BodyCapture> _readBoundedBody(HttpClientResponse response) async {
    final iterator = StreamIterator<List<int>>(response);
    final bytes = BytesBuilder(copy: false);
    final deadline = Stopwatch()..start();
    var truncated = false;
    try {
      while (true) {
        final remainingTime = _timeout - deadline.elapsed;
        if (remainingTime <= Duration.zero) throw TimeoutException('API response body read timed out.');
        if (!await iterator.moveNext().timeout(remainingTime)) break;
        final chunk = iterator.current;
        final remaining = maxApiResponseBytes - bytes.length;
        if (chunk.length > remaining) {
          if (remaining > 0) bytes.add(chunk.sublist(0, remaining));
          truncated = true;
          break;
        }
        bytes.add(chunk);
        if (bytes.length == maxApiResponseBytes) {
          truncated = response.contentLength < 0 || response.contentLength > maxApiResponseBytes;
          break;
        }
      }
    } finally {
      await iterator.cancel();
    }
    return _BodyCapture(bytes.takeBytes(), truncated);
  }

  /// Deterministic, local-only API response inspection. It never returns or stores
  /// the raw body; evidence contains only bounded metadata and redacted field paths.
  static ApiResponseAnalysis analyzeApiResponse({
    required List<int> body,
    required String? contentType,
    required bool truncated,
  }) {
    final findings = <SecurityFinding>[];
    final evidence = <String>[];
    if (body.isEmpty) {
      evidence.add('Response body was empty.');
      if (truncated) evidence.add('Response body exceeded the inspection limit.');
      return ApiResponseAnalysis(findings: findings, evidence: evidence);
    }

    final text = utf8.decode(body, allowMalformed: true);
    final contentTypeIsJson = contentType?.toLowerCase().contains('json') ?? false;
    if (_serverErrorDisclosurePattern.hasMatch(text)) {
      findings.add(const SecurityFinding(
        title: 'Detailed server error information may be exposed in the API response',
        severity: FindingSeverity.medium,
        recommendation: 'Return a generic client error and keep stack traces, SQL details, and internal paths in server-side logs.',
      ));
      evidence.add('Potential stack-trace or database-error signature observed; raw text was not retained.');
    }

    var validJson = false;
    Object? decoded;
    if (truncated) {
      evidence.add('JSON syntax validation skipped because only a bounded prefix was read.');
    } else {
      try {
        decoded = jsonDecode(text);
        validJson = true;
      } on FormatException {
        if (contentTypeIsJson) {
          findings.add(const SecurityFinding(
            title: 'Response declared JSON but did not parse as JSON',
            severity: FindingSeverity.low,
            recommendation: 'Return a valid JSON document matching the declared media type, or use the correct Content-Type.',
          ));
          evidence.add('JSON parse failed; response content was not retained.');
        }
      }
    }

    if (validJson) {
      evidence.add('Response body is valid JSON.');
      final seenSensitivePaths = <String>{};
      void visit(Object? value, String path, [int depth = 0]) {
        if (depth >= 16) return;
        if (value is Map) {
          for (final entry in value.entries) {
            final key = _safeJsonPathSegment(entry.key.toString());
            final childPath = '$path.$key';
            final child = entry.value;
            final nonEmpty = child != null && child.toString().isNotEmpty;
            if (nonEmpty &&
                seenSensitivePaths.length < 12 &&
                _sensitiveJsonKeyPattern.hasMatch(key) &&
                seenSensitivePaths.add(childPath)) {
              findings.add(SecurityFinding(
                title: 'Potentially sensitive API field observed: $childPath',
                severity: FindingSeverity.low,
                recommendation: 'Confirm this field is intended for this caller; omit secrets and enforce object- and field-level authorization.',
              ));
              evidence.add('Sensitive-looking field present at $childPath; value redacted.');
            }
            if (child is Map || child is List) visit(child, childPath, depth + 1);
          }
        } else if (value is List) {
          for (var index = 0; index < value.length; index++) {
            final child = value[index];
            if (child is Map || child is List) visit(child, '$path[$index]', depth + 1);
          }
        }
      }

      visit(decoded, r'$');
      if (seenSensitivePaths.isEmpty) evidence.add('No sensitive-looking JSON field names were observed by the local rules.');
    }
    if (truncated) evidence.add('Only the first ${maxApiResponseBytes} bytes were inspected; the body was truncated and findings may be incomplete.');
    if (findings.isEmpty && evidence.isEmpty) evidence.add('No configured response indicators were observed.');
    return ApiResponseAnalysis(findings: findings, evidence: evidence);
  }

  static String _safeJsonPathSegment(String key) {
    if (key.length > 64 || _jwtValuePattern.hasMatch(key)) return '[redacted-key]';
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
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
