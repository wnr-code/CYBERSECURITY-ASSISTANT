import 'dart:async';
import 'dart:convert';
import 'dart:io';

class GitHubRepository {
  const GitHubRepository({required this.owner, required this.name, required this.description});

  final String owner;
  final String name;
  final String description;

  String get fullName => '$owner/$name';
}

/// Repositories are sources for review and metadata only, never executable trust.
const githubReferenceRepositories = <GitHubRepository>[
  GitHubRepository(
    owner: 'AKCodez',
    name: 'hackingtool-plugin',
    description: 'Tool-catalog and workflow reference.',
  ),
  GitHubRepository(
    owner: '4nzu',
    name: 'hackingtool',
    description: 'Tool-category and workflow reference.',
  ),
  GitHubRepository(
    owner: 'ggml-org',
    name: 'llama.cpp',
    description: 'Local inference runtime reference.',
  ),
  GitHubRepository(
    owner: 'termux',
    name: 'termux-app',
    description: 'Optional Android terminal environment reference.',
  ),
];

class GitHubReleaseAsset {
  const GitHubReleaseAsset({
    required this.name,
    required this.sizeBytes,
    required this.contentType,
    required this.downloadUrl,
    required this.sha256,
  });

  final String name;
  final int sizeBytes;
  final String? contentType;
  final Uri downloadUrl;
  final String? sha256;
}

class GitHubRelease {
  const GitHubRelease({
    required this.repository,
    required this.tag,
    required this.title,
    required this.releaseUrl,
    required this.publishedAt,
    required this.assets,
  });

  final GitHubRepository repository;
  final String tag;
  final String title;
  final Uri releaseUrl;
  final DateTime? publishedAt;
  final List<GitHubReleaseAsset> assets;
}

class GitHubReleaseException implements Exception {
  const GitHubReleaseException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GitHubReleaseClient {
  static const _maxResponseBytes = 512 * 1024;
  static const _timeout = Duration(seconds: 12);

  Future<GitHubRelease> fetchLatest(GitHubRepository repository) async {
    if (!githubReferenceRepositories.any((entry) => entry.fullName == repository.fullName)) {
      throw const GitHubReleaseException('This repository is not in the app reference allowlist.');
    }

    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final uri = Uri.https('api.github.com', '/repos/${repository.owner}/${repository.name}/releases/latest');
      final request = await client.getUrl(uri).timeout(_timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Cybersecurity-Assistant/0.1');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode == HttpStatus.notFound) {
        await response.listen((_) {}).cancel();
        throw GitHubReleaseException('No published latest release was found for ${repository.fullName}.');
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.listen((_) {}).cancel();
        throw GitHubReleaseException('GitHub API returned HTTP ${response.statusCode}. Try again later.');
      }
      final body = await _readLimited(response).timeout(_timeout);
      return parseLatestRelease(body, repository);
    } on TimeoutException {
      throw const GitHubReleaseException('GitHub release lookup timed out.');
    } on SocketException {
      throw const GitHubReleaseException('Could not reach the GitHub API. Check network access.');
    } on HandshakeException {
      throw const GitHubReleaseException('GitHub TLS certificate validation failed.');
    } on HttpException {
      throw const GitHubReleaseException('GitHub returned an HTTP protocol error.');
    } on FormatException {
      throw const GitHubReleaseException('GitHub returned invalid release metadata.');
    } finally {
      client.close(force: true);
    }
  }

  GitHubRelease parseLatestRelease(String body, GitHubRepository repository) {
    if (!githubReferenceRepositories.any((entry) => entry.fullName == repository.fullName)) {
      throw const GitHubReleaseException('This repository is not in the app reference allowlist.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const GitHubReleaseException('Release metadata has an unexpected format.');
    }

    final tag = decoded['tag_name'];
    final title = decoded['name'];
    final htmlUrl = decoded['html_url'];
    if (tag is! String || tag.isEmpty || tag.length > 200 || title is! String || title.length > 500 || htmlUrl is! String) {
      throw const GitHubReleaseException('Release metadata is missing required fields.');
    }
    final releaseUrl = _validatedGitHubUrl(htmlUrl, repository, releasePage: true);
    final publishedString = decoded['published_at'];
    final publishedAt = publishedString is String ? DateTime.tryParse(publishedString)?.toUtc() : null;
    final rawAssets = decoded['assets'];
    final assets = <GitHubReleaseAsset>[];
    if (rawAssets is List) {
      for (final rawAsset in rawAssets.take(100)) {
        if (rawAsset is! Map<String, dynamic>) continue;
        final name = rawAsset['name'];
        final size = rawAsset['size'];
        final downloadUrl = rawAsset['browser_download_url'];
        if (name is! String || name.isEmpty || name.length > 255 || size is! int || size < 0 || downloadUrl is! String) {
          continue;
        }
        final validatedUrl = _validatedGitHubUrl(downloadUrl, repository, releasePage: false);
        final digest = rawAsset['digest'];
        final sha256 = digest is String && RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest)
            ? digest.substring('sha256:'.length).toLowerCase()
            : null;
        final contentType = rawAsset['content_type'];
        assets.add(GitHubReleaseAsset(
          name: name,
          sizeBytes: size,
          contentType: contentType is String && contentType.length <= 160 ? contentType : null,
          downloadUrl: validatedUrl,
          sha256: sha256,
        ));
      }
    }

    return GitHubRelease(
      repository: repository,
      tag: tag,
      title: title.isEmpty ? tag : title,
      releaseUrl: releaseUrl,
      publishedAt: publishedAt,
      assets: assets,
    );
  }

  Future<String> _readLimited(HttpClientResponse response) async {
    final bytes = <int>[];
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > _maxResponseBytes) {
        throw const GitHubReleaseException('GitHub release metadata exceeded the response size limit.');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Uri _validatedGitHubUrl(String value, GitHubRepository repository, {required bool releasePage}) {
    final uri = Uri.tryParse(value);
    final expectedPathPrefix = releasePage
        ? '/${repository.owner}/${repository.name}/releases/tag/'
        : '/${repository.owner}/${repository.name}/releases/download/';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith(expectedPathPrefix)) {
      throw const GitHubReleaseException('GitHub returned a release URL outside the expected repository.');
    }
    return uri;
  }
}
