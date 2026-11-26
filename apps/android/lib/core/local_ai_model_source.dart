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
  });

  final String repository;
  final String author;
  final String revision;
  final String license;
  final String fileName;
  final int sizeBytes;
  final String sha256Hex;
}

class LocalAiDownloadResponse {
  const LocalAiDownloadResponse({
    required this.statusCode,
    required this.contentLength,
    required this.body,
    required this.dispose,
  });
  final int statusCode;
  final int? contentLength;
  final Stream<List<int>> body;
  final Future<void> Function() dispose;
}

abstract interface class LocalAiArtifactSource {
  Future<LocalAiPublisherFile> fetchPublisherMetadata(LocalAiModelManifest manifest);
  Future<LocalAiDownloadResponse> openPinnedDownload(LocalAiModelManifest manifest);
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
    final uri = Uri.parse('$_apiOrigin/api/models/${manifest.repository}/revision/${manifest.revision}?blobs=true');
    if (uri.scheme != 'https' || uri.host != 'huggingface.co') {
      throw const LocalAiModelInstallException('Publisher metadata URL is not the official HTTPS Hugging Face API.');
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

      return parsePublisherMetadataJson(utf8.decode(bytes.takeBytes(), allowMalformed: false), manifest);
    } finally {
      await response.dispose();
    }
  }

  static LocalAiPublisherFile parsePublisherMetadataJson(String body, LocalAiModelManifest manifest) {
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
    final license = cardData is Map<String, dynamic> ? cardData['license'] : null;
    final siblings = decoded['siblings'];
    if (repository != manifest.repository || author != owner || revision != manifest.revision ||
        license is! String || license.toLowerCase() != manifest.license.toLowerCase()) {
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
    final lfsSize = lfs is Map<String, dynamic> ? lfs['size'] : null;
    final rawSize = file['size'];
    final metadataSha = objectId is String ? objectId.replaceFirst(RegExp(r'^sha256:'), '').toLowerCase() : '';
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
  Future<LocalAiDownloadResponse> openPinnedDownload(LocalAiModelManifest manifest) async {
    final uri = Uri.parse(manifest.downloadUrl);
    if (uri.scheme != 'https' || uri.host != 'huggingface.co' ||
        uri.path != '/${manifest.repository}/resolve/${manifest.revision}/${manifest.fileName}') {
      throw const LocalAiModelInstallException('Pinned download URL is not the exact official HTTPS resolve URL.');
    }
    final response = await _request(uri, allowCdnRedirects: true);
    return LocalAiDownloadResponse(
      statusCode: response.statusCode,
      contentLength: response.contentLength >= 0 ? response.contentLength : null,
      body: response.body,
      dispose: response.dispose,
    );
  }

  Future<_SourceResponse> _request(Uri initial, {required bool allowCdnRedirects}) async {
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
        return _SourceResponse(response.statusCode, response.contentLength, response, () async => client.close(force: true));
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
  const _SourceResponse(this.statusCode, this.contentLength, this.body, this.dispose);
  final int statusCode;
  final int contentLength;
  final HttpClientResponse body;
  final Future<void> Function() dispose;
}
