import 'dart:io';

class PolicyException implements Exception {
  const PolicyException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthorizedTarget {
  const AuthorizedTarget({required this.host, required this.uri, required this.scope});
  final String host;
  final Uri uri;
  /// A query-free target identifier shared by checks in one assessment.
  final String scope;
}

/// Validates a narrow, explicitly approved target before any network operation.
/// This is a user-consent boundary, not proof of legal authorization.
class PolicyEngine {
  static final _hostnamePattern = RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\.(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?))*$',
  );

  static bool _isValidIpv4(String host) {
    final octets = host.split('.');
    if (octets.length != 4) return false;
    for (final octet in octets) {
      if (octet.isEmpty || octet.length > 3 || (octet.length > 1 && octet.startsWith('0'))) return false;
      final value = int.tryParse(octet);
      if (value == null || value > 255) return false;
    }
    return true;
  }

  static String _normalizedHostname(String input) => input.toLowerCase().replaceFirst(RegExp(r'\.$'), '');

  static bool isCloudMetadataHostname(String input) {
    final host = _normalizedHostname(input);
    return host == 'metadata' ||
        host == 'metadata.google.internal' ||
        host == 'metadata.azure.internal' ||
        host == 'metadata.google';
  }

  static bool isRestrictedHostname(String input) {
    final host = _normalizedHostname(input);
    return host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        isCloudMetadataHostname(host);
  }

  static bool isCloudMetadataAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 169 && bytes[1] == 254 && bytes[2] == 169 && bytes[3] == 254;
    }
    final isIpv4Mapped = bytes.take(10).every((byte) => byte == 0) && bytes[10] == 255 && bytes[11] == 255;
    if (isIpv4Mapped) {
      return isCloudMetadataAddress(InternetAddress.fromRawAddress(bytes.sublist(12), type: InternetAddressType.IPv4));
    }
    final normalized = address.address.toLowerCase();
    return normalized == 'fd00:ec2::254' || normalized == 'fd20:ce::254';
  }

  static const _runtimeToolCapabilities = <String, Set<String>>{
    'dns_lookup': {'network'},
    'tls_inspector': {'network'},
    'http_headers': {'network'},
    'response_analyzer': {},
  };

  /// Policy gate for the only built-in runtime operations. It is intentionally
  /// a closed allowlist: no command strings or dynamically loaded tool IDs pass.
  void authorizeRuntimeTool({
    required String toolId,
    required bool networkAuthorized,
    required Set<String> requiredCapabilities,
    required Set<String> grantedCapabilities,
  }) {
    final expected = _runtimeToolCapabilities[toolId];
    if (expected == null) throw const PolicyException('Tool is not authorized by the runtime policy.');
    if (requiredCapabilities.length != expected.length || !requiredCapabilities.containsAll(expected)) {
      throw const PolicyException('Tool requested capabilities outside its least-privilege policy.');
    }
    if (!grantedCapabilities.containsAll(expected)) {
      throw const PolicyException('Required runtime capabilities were not granted.');
    }
    if (expected.contains('network') && !networkAuthorized) {
      throw const PolicyException('Confirm that you own or are authorized to assess this target.');
    }
  }

  /// Returns true for loopback, private, link-local, metadata, multicast,
  /// documentation, benchmark, unspecified, and other non-global IP ranges.
  static bool isRestrictedAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      final first = bytes[0];
      final second = bytes[1];
      final third = bytes[2];
      return first == 0 ||
          first == 10 ||
          first == 127 ||
          (first == 169 && second == 254) ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168) ||
          (first == 100 && second >= 64 && second <= 127) ||
          (first == 198 && (second == 18 || second == 19)) ||
          (first == 192 && second == 0 && third == 0) ||
          (first == 192 && second == 0 && third == 2) ||
          (first == 192 && second == 88 && third == 99) ||
          (first == 198 && second == 51 && third == 100) ||
          (first == 203 && second == 0 && third == 113) ||
          first >= 224;
    }

    final isIpv4Mapped = bytes.take(10).every((byte) => byte == 0) && bytes[10] == 255 && bytes[11] == 255;
    if (isIpv4Mapped) {
      return isRestrictedAddress(InternetAddress.fromRawAddress(bytes.sublist(12), type: InternetAddressType.IPv4));
    }
    final first = bytes[0];
    final second = bytes[1];
    final unspecified = bytes.every((byte) => byte == 0);
    final loopback = bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
    final nat64Prefix = first == 0x00 && second == 0x64 && bytes[2] == 0xff && bytes[3] == 0x9b;
    final nat64WellKnown = nat64Prefix && bytes.skip(4).take(8).every((byte) => byte == 0);
    final nat64LocalUse = nat64Prefix && bytes[4] == 0x00 && bytes[5] == 0x01;

    final ipv6SpecialPurpose = first == 0x20 && second == 0x01 &&
        ((bytes[2] <= 0x01) || // IETF protocol assignments, including Teredo
            (bytes[2] == 0x00 && (bytes[3] == 0x10 || bytes[3] == 0x20)) || // ORCHID ranges
            (bytes[2] == 0x0d && bytes[3] == 0xb8)); // Documentation
    return unspecified ||
        loopback ||
        (first & 0xfe) == 0xfc ||
        (first == 0xfe && (second & 0xc0) == 0x80) ||
        first == 0xff ||
        nat64WellKnown ||
        nat64LocalUse ||
        (first == 0x20 && second == 0x02) || // 6to4 embeds an IPv4 destination
        ipv6SpecialPurpose ||
        // Only global unicast 2000::/3 is permitted; reject other special-use ranges.
        (first & 0xe0) != 0x20;
  }

  AuthorizedTarget validateTarget(String input, {required bool authorized, bool allowPrivateNetwork = false}) {
    if (!authorized) {
      throw const PolicyException('Confirm that you own or are authorized to test this target.');
    }

    final value = input.trim();
    if (value.isEmpty) throw const PolicyException('Enter a target domain.');
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null) throw const PolicyException('Enter a valid domain name or HTTPS URL.');
    if (uri.scheme != 'https') {
      throw const PolicyException('Only HTTPS targets are supported by these checks.');
    }

    late final String parsedHost;
    late final String userInfo;
    late final int port;
    try {
      parsedHost = uri.host;
      userInfo = uri.userInfo;
      port = uri.port;
    } on FormatException {
      throw const PolicyException('Enter a valid domain name or HTTPS URL.');
    }
    if (!uri.hasAuthority || parsedHost.isEmpty) {
      throw const PolicyException('Enter a valid domain name or HTTPS URL.');
    }
    if (userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const PolicyException('URLs with credentials, query parameters, or fragments are not accepted.');
    }
    if (port != 443) {
      throw const PolicyException('Only the standard HTTPS port 443 is supported.');
    }
    if (uri.path.length > 2048 || uri.path.contains('\r') || uri.path.contains('\n')) {
      throw const PolicyException('The HTTPS request path is invalid or too long.');
    }

    final host = parsedHost.toLowerCase();
    final literalAddress = InternetAddress.tryParse(host);
    if (isCloudMetadataHostname(host) || (literalAddress != null && isCloudMetadataAddress(literalAddress))) {
      throw const PolicyException('Cloud metadata destinations are blocked, including when local/private targets are enabled.');
    }
    if (!allowPrivateNetwork &&
        (isRestrictedHostname(host) || (literalAddress != null && isRestrictedAddress(literalAddress)))) {
      throw const PolicyException('Local, private, and link-local targets are blocked unless explicitly allowed.');
    }
    if (RegExp(r'^(?:[0-9]+|0x[0-9a-f]+)$', caseSensitive: false).hasMatch(host)) {
      throw const PolicyException('Numeric shorthand and hexadecimal IP addresses are not accepted.');
    }
    if (!_hostnamePattern.hasMatch(host)) {
      throw const PolicyException('This prototype accepts DNS hostnames and IPv4 addresses only.');
    }
    if (host.contains('.') && RegExp(r'^[0-9.]+$').hasMatch(host) && !_isValidIpv4(host)) {
      throw const PolicyException('Enter a valid IPv4 address.');
    }
    final normalizedUri = uri.replace(scheme: 'https', host: host, port: null, userInfo: '');
    final normalizedPath = normalizedUri.path.isEmpty ? '/' : normalizedUri.path;
    final requestUri = normalizedUri.replace(path: normalizedPath);
    final scope = normalizedPath == '/' ? host : '$host$normalizedPath';
    return AuthorizedTarget(host: host, uri: requestUri, scope: scope);
  }
}
