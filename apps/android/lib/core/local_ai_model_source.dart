import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'local_ai_model_manifest.dart';

class LocalAiPublisherFile {
  const LocalAiPublisherFile({
    required this.repository,
    required this.author,
    required this.revision,
    required this.license,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256Hex,
    this.licenseRepository = '',
    this.licenseRevision = '',
  });

  final String repository;
  final String author;
  final String revision;
  final String license;
  final String fileName;
  final int sizeBytes;
  final String sha256Hex;
  final String licenseRepository;
  final String licenseRevision;
}

class LocalAiDownloadResponse {
  const LocalAiDownloadResponse({
    required this.statusCode,
    required this.contentLength,
    required this.body,
    required this.dispose,
    this.contentRange,
  });
  final int statusCode;
  final int? contentLength;
  final String? contentRange;
  final Stream<List<int>> body;
  final Future<void> Function() dispose;
}

abstract interface class LocalAiArtifactSource {
  Future<LocalAiPublisherFile> fetchPublisherMetadata(LocalAiModelManifest manifest);
  Future<LocalAiDownloadResponse> openPinnedDownload(
    LocalAiModelManifest manifest, {
    required int rangeStart,
    required int rangeEnd,
  });
}

/// Talks only to the official Hugging Face Hub API and the immutable resolve
/// URL. Redirects are constrained to HTTPS Hugging Face/CDN domains, and the
/// caller hashes the complete downloaded file before native load.
class HuggingFaceLocalAiArtifactSource implements LocalAiArtifactSource {
  HuggingFaceLocalAiArtifactSource({HttpClient Function()? clientFactory}) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  static const _metadataLimit = 2 * 1024 * 1024;
  static const _maxRedirects = 5;
  static const _apiOrigin = 'https://huggingface.co';

  @override
  Future<LocalAiPublisherFile> fetchPublisherMetadata(LocalAiModelManifest manifest) async {
    final uri = Uri.parse('$_apiOrigin/api/models/${manifest.repository}/revision/${manifest.revision}?blobs=true&full=true');
    if (uri.scheme != 'https' || uri.host != 'huggingface.co') {
      throw const LocalAiModelInstallException('Publisher metadata URL is not the official HTTPS Hugging Face API.');
    }
    final repositoryMetadata = await _fetchHubJson(uri);
    final licenseUri = Uri.parse('$_apiOrigin/api/models/${manifest.licenseRepository}/revision/${manifest.licenseRevision}?full=true');
    final licenseMetadata = await _fetchHubJson(licenseUri);
    final expectedOwner = manifest.repository.split('/').first;
    final officialLicense = licenseMetadata['cardData'];
    if (licenseMetadata['id'] != manifest.licenseRepository ||
        licenseMetadata['author'] != expectedOwner ||
        licenseMetadata['sha'] != manifest.licenseRevision ||
        officialLicense is! Map<String, dynamic> ||
        officialLicense['license'] is! String ||
        (officialLicense['license'] as String).toLowerCase() != manifest.license.toLowerCase()) {
      throw const LocalAiModelInstallException('The pinned official base-model license record did not match the publisher, revision, or app license pin. Installation was blocked.');
    }

    final publisherFile = parsePublisherMetadataJson(
      jsonEncode(repositoryMetadata),
      manifest,
      verifiedLicense: officialLicense['license'] as String,
    );
    return LocalAiPublisherFile(
      repository: publisherFile.repository,
      author: publisherFile.author,
      revision: publisherFile.revision,
      license: publisherFile.license,
      fileName: publisherFile.fileName,
      sizeBytes: publisherFile.sizeBytes,
      sha256Hex: publisherFile.sha256Hex,
      licenseRepository: manifest.licenseRepository,
      licenseRevision: manifest.licenseRevision,
    );
  }

  Future<Map<String, dynamic>> _fetchHubJson(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != 'huggingface.co' || !uri.path.startsWith('/api/models/')) {
      throw const LocalAiModelInstallException('Metadata URL is not the official HTTPS Hugging Face API.');
    }
    final response = await _request(uri, allowCdnRedirects: false);
    try {
      if (response.statusCode != HttpStatus.ok) {
        await response.body.drain<void>();
        throw LocalAiModelInstallException('Official publisher metadata request failed with HTTP ${response.statusCode}. Check internet and retry.');
      }
      final bytes = BytesBuilder(copy: false);
      var count = 0;
      try {
        await for (final chunk in response.body.timeout(const Duration(seconds: 30))) {
          count += chunk.length;
          if (count > _metadataLimit) throw const LocalAiModelInstallException('Publisher metadata exceeded the safe 2 MiB response limit.');
          bytes.add(chunk);
        }
      } on LocalAiModelInstallException {
        rethrow;
      } catch (_) {
        throw const LocalAiModelInstallException('Could not read official publisher metadata. Check internet and retry.');
      }
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes(), allowMalformed: false));
      if (decoded is! Map<String, dynamic>) throw const LocalAiModelInstallException('Official metadata had an unexpected structure.');
      return decoded;
    } on FormatException {
      throw const LocalAiModelInstallException('Official publisher metadata was not valid UTF-8 JSON.');
    } finally {
      await response.dispose();
    }
  }

  static LocalAiPublisherFile parsePublisherMetadataJson(String body, LocalAiModelManifest manifest, {String? verifiedLicense}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const LocalAiModelInstallException('Official publisher metadata was not valid UTF-8 JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const LocalAiModelInstallException('Official publisher metadata had an unexpected structure.');
    }
    final owner = manifest.repository.split('/').first;
    final repository = decoded['id'];
    final author = decoded['author'];
    final revision = decoded['sha'];
    final cardData = decoded['cardData'];
    final repositoryLicense = cardData is Map<String, dynamic> ? cardData['license'] : null;
    if (repositoryLicense is String && verifiedLicense != null && repositoryLicense.toLowerCase() != verifiedLicense.toLowerCase()) {
      throw const LocalAiModelInstallException('The GGUF repository and pinned base-model license records conflict. Installation was blocked.');
    }
    final license = repositoryLicense is String ? repositoryLicense : verifiedLicense;
    final siblings = decoded['siblings'];
    if (repository != manifest.repository || author != owner || revision != manifest.revision ||
        license == null || license.toLowerCase() != manifest.license.toLowerCase()) {
      throw const LocalAiModelInstallException('Official publisher, repository, immutable revision, or license does not match the app pin. Installation was blocked.');
    }
    if (siblings is! List) {
      throw const LocalAiModelInstallException('Official metadata did not include the repository file list. Installation was blocked.');
    }
    final matchingFiles = siblings.whereType<Map<String, dynamic>>().where((row) => row['rfilename'] == manifest.fileName).toList();
    if (matchingFiles.length != 1) {
      throw const LocalAiModelInstallException('The exact pinned GGUF file was not uniquely present in the official revision. Installation was blocked.');
    }
    final file = matchingFiles.single;
    final lfs = file['lfs'];
    final objectId = lfs is Map<String, dynamic> ? lfs['oid'] : null;
    final lfsSha256 = lfs is Map<String, dynamic> ? lfs['sha256'] : null;
    final lfsSize = lfs is Map<String, dynamic> ? lfs['size'] : null;
    final rawSize = file['size'];
    final oidSha = objectId is String ? objectId.replaceFirst(RegExp(r'^sha256:'), '').toLowerCase() : null;
    final directSha = lfsSha256 is String ? lfsSha256.toLowerCase() : null;
    if (oidSha != null && directSha != null && oidSha != directSha) {
      throw const LocalAiModelInstallException('Official GGUF metadata contains conflicting SHA-256 values. Installation was blocked.');
    }
    final metadataSha = directSha ?? oidSha ?? '';
    if (rawSize is! int || lfsSize is! int || rawSize != manifest.fileSizeBytes || lfsSize != manifest.fileSizeBytes ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(metadataSha) || metadataSha != manifest.sha256Hex) {
      throw const LocalAiModelInstallException('Official GGUF size or publisher SHA-256 does not match the app pin. Installation was blocked.');
    }
    return LocalAiPublisherFile(
      repository: repository as String,
      author: author as String,
      revision: revision as String,
      license: license,
      fileName: manifest.fileName,
      sizeBytes: rawSize,
      sha256Hex: metadataSha,
    );
  }

  @override
  Future<LocalAiDownloadResponse> openPinnedDownload(
    LocalAiModelManifest manifest, {
    required int rangeStart,
    required int rangeEnd,
  }) async {
    final uri = Uri.parse(manifest.downloadUrl);
    if (uri.scheme != 'https' || uri.host != 'huggingface.co' ||
        uri.path != '/${manifest.repository}/resolve/${manifest.revision}/${manifest.fileName}' ||
        rangeStart < 0 || rangeEnd < rangeStart || rangeEnd >= manifest.fileSizeBytes) {
      throw const LocalAiModelInstallException('Pinned download URL or requested byte range is invalid.');
    }
    final response = await _request(uri, allowCdnRedirects: true, rangeStart: rangeStart, rangeEnd: rangeEnd);
    return LocalAiDownloadResponse(
      statusCode: response.statusCode,
      contentLength: response.contentLength >= 0 ? response.contentLength : null,
      contentRange: response.contentRange,
      body: response.body,
      dispose: response.dispose,
    );
  }

  Future<_SourceResponse> _request(
    Uri initial, {
    required bool allowCdnRedirects,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final client = _clientFactory()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 90);
    var transferred = false;
    try {
      var uri = initial;
      for (var redirects = 0; redirects <= _maxRedirects; redirects++) {
        if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.host.isEmpty ||
            (uri.host != 'huggingface.co' && !(allowCdnRedirects && _isHuggingFaceCdn(uri.host)))) {
          throw const LocalAiModelInstallException('Publisher response redirected outside the approved HTTPS Hugging Face hosts.');
        }
        final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if ((rangeStart == null) != (rangeEnd == null)) {
          throw const LocalAiModelInstallException('Incomplete byte range requested from the official model source.');
        }
        if (rangeStart != null && rangeEnd != null) {
          request.headers.set('range', 'bytes=$rangeStart-$rangeEnd');
        }
        request.headers.set(HttpHeaders.userAgentHeader, 'CybersecurityAssistant-LocalAI/1.0');
        request.headers.set(HttpHeaders.acceptHeader, uri.path.startsWith('/api/') ? 'application/json' : 'application/octet-stream');
        final response = await request.close().timeout(const Duration(seconds: 30));
        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null || redirects == _maxRedirects) {
            throw const LocalAiModelInstallException('Publisher download had a missing or excessive redirect chain.');
          }
          if (!allowCdnRedirects) {
            throw const LocalAiModelInstallException('Publisher metadata unexpectedly redirected. Installation was blocked.');
          }
          uri = uri.resolve(location);
          continue;
        }
        transferred = true;
        return _SourceResponse(
          response.statusCode,
          response.contentLength,
          response.headers.value('content-range'),
          response,
          () async => client.close(force: true),
        );
      }
      throw const LocalAiModelInstallException('Publisher download exceeded the redirect limit.');
    } on LocalAiModelInstallException {
      rethrow;
    } on SocketException {
      throw const LocalAiModelInstallException('Network connection to the official model source failed. Check internet and retry; no model was installed.');
    } on HttpException {
      throw const LocalAiModelInstallException('The official model source connection failed. Check internet and retry; no model was installed.');
    } on TimeoutException {
      throw const LocalAiModelInstallException('The official model source timed out. Check internet and retry; no model was installed.');
    } finally {
      if (!transferred) client.close(force: true);
    }
  }

  static bool _isHuggingFaceCdn(String host) =>
      host.endsWith('.huggingface.co') || host == 'hf.co' || host.endsWith('.hf.co');
}

class _SourceResponse {
  const _SourceResponse(this.statusCode, this.contentLength, this.contentRange, this.body, this.dispose);
  final int statusCode;
  final int contentLength;
  final String? contentRange;
  final HttpClientResponse body;
  final Future<void> Function() dispose;
}
