class PolicyException implements Exception {
  const PolicyException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthorizedTarget {
  const AuthorizedTarget({required this.host, required this.uri});
  final String host;
  final Uri uri;
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

  AuthorizedTarget validateTarget(String input, {required bool authorized}) {
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
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const PolicyException('Use the origin only; checks are limited to the root path.');
    }

    final host = parsedHost.toLowerCase();
    if (!_hostnamePattern.hasMatch(host)) {
      throw const PolicyException('This prototype accepts DNS hostnames and IPv4 addresses only.');
    }
    if (host.contains('.') && RegExp(r'^[0-9.]+$').hasMatch(host) && !_isValidIpv4(host)) {
      throw const PolicyException('Enter a valid IPv4 address.');
    }
    return AuthorizedTarget(host: host, uri: Uri.https(host, '/'));
  }
}
