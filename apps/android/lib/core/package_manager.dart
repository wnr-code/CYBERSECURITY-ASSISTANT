import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'policy_engine.dart';

enum MarketCategory {
  securityTools,
  runtime,
  plugins,
  aiModels,
  knowledgePacks,
  cloudApiConnectors,
}

enum PackageStatus {
  available,
  downloading,
  downloaded,
  verifying,
  installed,
  updateAvailable,
  incompatible,
  failed,
}

enum PackageCompatibility { compatible, limitedCompatibility, incompatible, unsupported }

enum PackagePayloadType { jsonData, opaqueData, archive, nativeExecutable }

class MarketPackage {
  const MarketPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.version,
    required this.downloadSizeBytes,
    required this.officialSource,
    required this.officialSourceUri,
    required this.license,
    required this.platforms,
    required this.architectures,
    required this.dependencies,
    required this.runtimeRequirements,
    required this.permissions,
    required this.compatibility,
    required this.installationGuide,
    required this.payloadType,
    this.sha256,
    this.signature,
    this.downloadUri,
    this.bundledAssetPath,
    this.isBundledCore = false,
  });

  final String id;
  final String name;
  final String description;
  final MarketCategory category;
  final String version;
  final int? downloadSizeBytes;
  final String officialSource;
  final Uri officialSourceUri;
  final String license;
  final List<String> platforms;
  final List<String> architectures;
  final List<String> dependencies;
  final List<String> runtimeRequirements;
  final List<String> permissions;
  final PackageCompatibility compatibility;
  final String installationGuide;
  final PackagePayloadType payloadType;
  final String? sha256;
  /// Optional base64 detached signature. A configured verifier is mandatory if present.
  final String? signature;
  final Uri? downloadUri;
  /// Used only by the offline, bundled demo package.
  final String? bundledAssetPath;
  final bool isBundledCore;

  bool get hasArtifact => downloadUri != null || bundledAssetPath != null;
  bool get canBeInstalledAsData => payloadType == PackagePayloadType.jsonData || payloadType == PackagePayloadType.opaqueData;
}

class CompatibilityEnvironment {
  const CompatibilityEnvironment({
    required this.platform,
    this.architecture,
    this.availableRuntimes = const {},
  });

  final String platform;
  /// Null means the ABI could not be established; ABI-specific packages are limited, not declared ready.
  final String? architecture;
  final Set<String> availableRuntimes;
}

class PackageCompatibilityResult {
  const PackageCompatibilityResult(this.status, this.reasons);
  final PackageCompatibility status;
  final List<String> reasons;
}

class CompatibilityChecker {
  const CompatibilityChecker(this.environment);
  final CompatibilityEnvironment environment;

  PackageCompatibilityResult check(MarketPackage package) {
    if (package.compatibility == PackageCompatibility.unsupported) {
      return const PackageCompatibilityResult(PackageCompatibility.unsupported, ['Publisher marks this package unsupported.']);
    }
    if (package.compatibility == PackageCompatibility.incompatible) {
      return const PackageCompatibilityResult(PackageCompatibility.incompatible, ['Package metadata marks this package incompatible.']);
    }

    final reasons = <String>[];
    if (!package.platforms.any((platform) => platform.toLowerCase() == environment.platform.toLowerCase() || platform == 'Any')) {
      return PackageCompatibilityResult(PackageCompatibility.incompatible, ['Requires ${package.platforms.join(', ')}.']);
    }
    if (package.architectures.isNotEmpty && !package.architectures.contains('any')) {
      final architecture = environment.architecture;
      if (architecture == null) {
        reasons.add('Device CPU ABI is unknown; install readiness cannot be confirmed.');
      } else if (!package.architectures.contains(architecture)) {
        return PackageCompatibilityResult(
          PackageCompatibility.incompatible,
          ['Requires ${package.architectures.join(', ')}; detected $architecture.'],
        );
      }
    }

    final missingRuntime = package.runtimeRequirements.where((runtime) => !environment.availableRuntimes.contains(runtime)).toList();
    if (missingRuntime.isNotEmpty) {
      return PackageCompatibilityResult(PackageCompatibility.incompatible, ['Missing runtime(s): ${missingRuntime.join(', ')}.']);
    }
    if (package.compatibility == PackageCompatibility.limitedCompatibility || reasons.isNotEmpty) {
      return PackageCompatibilityResult(
        PackageCompatibility.limitedCompatibility,
        [...reasons, if (package.compatibility == PackageCompatibility.limitedCompatibility) 'Publisher marks this package as limited compatibility.'],
      );
    }
    return const PackageCompatibilityResult(PackageCompatibility.compatible, []);
  }
}

class PackageManagerException implements Exception {
  const PackageManagerException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DownloadedPackage {
  const DownloadedPackage(this.bytes);
  final Uint8List bytes;
}

abstract interface class PackageDownloader {
  Future<DownloadedPackage> download(MarketPackage package, {required int maxBytes, required Duration timeout});
}

class PackageDownloadManager {
  const PackageDownloadManager(this.downloader);
  final PackageDownloader downloader;

  Future<DownloadedPackage> download(MarketPackage package, {required int maxBytes, required Duration timeout}) async {
    final result = await downloader.download(package, maxBytes: maxBytes, timeout: timeout);
    if (result.bytes.length > maxBytes) throw const PackageManagerException('Package exceeds the configured download size limit.');
    return result;
  }
}

abstract interface class PackageSignatureVerifier {
  Future<bool> verify(MarketPackage package, Uint8List payload);
}

class BundledAndHttpPackageDownloader implements PackageDownloader {
  BundledAndHttpPackageDownloader({
    Set<String> trustedDownloadHosts = const {},
    HttpClient Function()? httpClientFactory,
    HostResolver? hostResolver,
  })  : _trustedDownloadHosts = trustedDownloadHosts.map((host) => host.toLowerCase()).toSet(),
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _hostResolver = hostResolver ?? InternetAddress.lookup;

  final Set<String> _trustedDownloadHosts;
  final HttpClient Function() _httpClientFactory;
  final HostResolver _hostResolver;

  @override
  Future<DownloadedPackage> download(MarketPackage package, {required int maxBytes, required Duration timeout}) async {
    final bundledAssetPath = package.bundledAssetPath;
    if (bundledAssetPath != null) {
      final data = await rootBundle.load(bundledAssetPath).timeout(timeout);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.length > maxBytes) throw const PackageManagerException('Package exceeds the configured download size limit.');
      return DownloadedPackage(Uint8List.fromList(bytes));
    }

    final uri = package.downloadUri;
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const PackageManagerException('A valid HTTPS package URL is required.');
    }
    if (!_trustedDownloadHosts.contains(uri.host.toLowerCase())) {
      throw const PackageManagerException('Package host is not in the user-configured trusted download source list.');
    }
    final deadline = Stopwatch()..start();
    Duration remaining() {
      final value = timeout - deadline.elapsed;
      if (value <= Duration.zero) throw TimeoutException('Package download timed out.');
      return value;
    }

    final addresses = await _hostResolver(uri.host).timeout(remaining());
    if (addresses.isEmpty || addresses.any((address) => PolicyEngine.isRestrictedAddress(address) || PolicyEngine.isCloudMetadataAddress(address))) {
      throw const PackageManagerException('Package source resolved to a local, reserved, or metadata address.');
    }

    final client = _httpClientFactory()..connectionTimeout = timeout;
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (requestUri, proxyHost, proxyPort) async {
      if (proxyHost != null ||
          requestUri.host.toLowerCase() != uri.host.toLowerCase() ||
          requestUri.port != 443) {
        throw const HttpException('Package request escaped its trusted HTTPS source.');
      }
      Object? lastError;
      for (final address in addresses) {
        ConnectionTask<Socket>? task;
        try {
          task = await Socket.startConnect(address, 443).timeout(remaining());
          await task.socket.timeout(remaining(), onTimeout: () {
            task?.cancel();
            throw TimeoutException('Package source connection timed out.');
          });
          return task;
        } on SocketException catch (error) {
          lastError = error;
          task?.cancel();
        } on TimeoutException {
          task?.cancel();
          rethrow;
        }
      }
      if (lastError is SocketException) throw lastError;
      throw const HttpException('No preflight-approved package source address could be reached.');
    };

    try {
      final request = await client.getUrl(uri).timeout(remaining());
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream, application/json;q=0.9');
      final response = await request.close().timeout(remaining());
      if (response.statusCode != HttpStatus.ok) {
        await response.listen((_) {}).cancel();
        throw PackageManagerException('Package source returned HTTP ${response.statusCode}; redirects are not followed.');
      }
      if (response.contentLength > maxBytes) {
        await response.listen((_) {}).cancel();
        throw const PackageManagerException('Package exceeds the configured download size limit.');
      }
      final builder = BytesBuilder(copy: false);
      final iterator = StreamIterator<List<int>>(response);
      try {
        while (await iterator.moveNext().timeout(remaining())) {
          final chunk = iterator.current;
          if (builder.length + chunk.length > maxBytes) {
            throw const PackageManagerException('Package exceeds the configured download size limit.');
          }
          builder.add(chunk);
        }
      } finally {
        await iterator.cancel();
      }
      return DownloadedPackage(builder.takeBytes());
    } on TimeoutException {
      throw const PackageManagerException('Package download timed out.');
    } on SocketException {
      throw const PackageManagerException('Could not reach the trusted package source.');
    } on HandshakeException {
      throw const PackageManagerException('Package source TLS validation failed.');
    } on HttpException {
      throw const PackageManagerException('Package source returned an HTTP protocol error.');
    } finally {
      client.close(force: true);
    }
  }
}

class VerifiedPackage {
  const VerifiedPackage({required this.package, required this.bytes, required this.sha256});
  final MarketPackage package;
  final Uint8List bytes;
  final String sha256;
}

class PackageVerifier {
  const PackageVerifier({this.signatureVerifier});
  final PackageSignatureVerifier? signatureVerifier;

  Future<VerifiedPackage> verify(MarketPackage package, Uint8List bytes) async {
    final expectedSize = package.downloadSizeBytes;
    if (expectedSize != null && bytes.length != expectedSize) {
      throw const PackageManagerException('Downloaded size does not match the catalogue metadata.');
    }
    final expectedSha = package.sha256?.toLowerCase();
    if (expectedSha == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha)) {
      throw const PackageManagerException('A valid SHA-256 checksum is required before installation.');
    }
    final actualSha = sha256.convert(bytes).toString();
    if (actualSha != expectedSha) throw const PackageManagerException('Package checksum verification failed.');

    final signature = package.signature;
    if (signature != null) {
      final verifier = signatureVerifier;
      if (verifier == null || !await verifier.verify(package, bytes)) {
        throw const PackageManagerException('Package signature could not be verified.');
      }
    }

    if (!package.canBeInstalledAsData) {
      throw const PackageManagerException('This package type is not installable: executable code is never loaded from Market.');
    }
    if (package.payloadType == PackagePayloadType.jsonData) {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != 1 ||
          decoded['packageId'] != package.id ||
          decoded['version'] != package.version ||
          decoded['content'] is! Map<String, dynamic>) {
        throw const PackageManagerException('Knowledge/data package manifest does not match its catalogue entry.');
      }
    }
    return VerifiedPackage(package: package, bytes: bytes, sha256: actualSha);
  }
}

class InstalledPackage {
  const InstalledPackage({required this.id, required this.version, required this.relativeFile, required this.sha256});
  final String id;
  final String version;
  final String relativeFile;
  final String sha256;
}

class PackageRegistry {
  PackageRegistry(this.file);
  final File file;
  final Map<String, InstalledPackage> _installed = {};

  List<InstalledPackage> get installed => List.unmodifiable(_installed.values);
  InstalledPackage? byId(String id) => _installed[id];
  bool contains(String id) => _installed.containsKey(id);

  Future<void> load() async {
    _installed.clear();
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) throw const FormatException('Registry must be a JSON list.');
      for (final row in decoded) {
        if (row is! Map<String, dynamic>) continue;
        final id = row['id'];
        final version = row['version'];
        final relativeFile = row['relativeFile'];
        final digest = row['sha256'];
        if (id is! String || !_isSafePackageId(id) ||
            version is! String || !_isSafeVersion(version) ||
            relativeFile is! String || digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
          continue;
        }
        final expectedRelative = p.join(id, version, 'payload.${_payloadExtension(relativeFile)}');
        if (relativeFile != expectedRelative) continue;
        final payload = File(p.join(file.parent.path, relativeFile));
        if (!await payload.exists() || await payload.length() > maxMarketPackageBytes) continue;
        final actualDigest = sha256.convert(await payload.readAsBytes()).toString();
        if (actualDigest != digest) continue;
        _installed[id] = InstalledPackage(id: id, version: version, relativeFile: relativeFile, sha256: digest);
      }
    } on FormatException {
      _installed.clear();
      throw const PackageManagerException('Local package registry is invalid; packages were not marked installed.');
    }
  }

  Future<void> record(InstalledPackage package) async {
    _installed[package.id] = package;
    await _save();
  }

  Future<void> remove(String id) async {
    _installed.remove(id);
    await _save();
  }

  Future<void> _save() async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode([
      for (final package in _installed.values)
        {
          'id': package.id,
          'version': package.version,
          'relativeFile': package.relativeFile,
          'sha256': package.sha256,
        },
    ]), flush: true);
    await temporary.rename(file.path);
  }
}

String _payloadExtension(String relativeFile) {
  final extension = p.extension(relativeFile).replaceFirst('.', '');
  return extension == 'json' ? 'json' : 'data';
}

bool _isSafePackageId(String value) => RegExp(r'^[a-z0-9][a-z0-9._-]{1,119}$').hasMatch(value) && !value.contains('..');
bool _isSafeVersion(String value) => RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$').hasMatch(value) && !value.contains('..');

class PackageInstaller {
  const PackageInstaller({required this.packageDirectory, required this.registry});
  final Directory packageDirectory;
  final PackageRegistry registry;

  Future<InstalledPackage> install(VerifiedPackage verified) async {
    final package = verified.package;
    if (!_isSafePackageId(package.id) || !_isSafeVersion(package.version)) {
      throw const PackageManagerException('Package ID or version is unsafe.');
    }
    final extension = package.payloadType == PackagePayloadType.jsonData ? 'json' : 'data';
    final previous = registry.byId(package.id);
    final relativeFile = p.join(package.id, package.version, 'payload.$extension');
    final destination = File(p.join(packageDirectory.path, relativeFile));
    final parent = destination.parent;
    await parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    try {
      await temporary.writeAsBytes(verified.bytes, flush: true);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      final installed = InstalledPackage(
        id: package.id,
        version: package.version,
        relativeFile: relativeFile,
        sha256: verified.sha256,
      );
      await registry.record(installed);
      if (previous != null && previous.version != package.version) {
        final oldVersionDirectory = Directory(p.join(packageDirectory.path, package.id, previous.version));
        if (await oldVersionDirectory.exists()) await oldVersionDirectory.delete(recursive: true);
      }
      return installed;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> uninstall(InstalledPackage package) async {
    if (!_isSafePackageId(package.id) || !_isSafeVersion(package.version)) {
      throw const PackageManagerException('Installed package registry contains an unsafe path.');
    }
    final expectedRelative = p.join(package.id, package.version, 'payload.${_payloadExtension(package.relativeFile)}');
    if (package.relativeFile != expectedRelative) throw const PackageManagerException('Installed package path is invalid.');
    final directory = Directory(p.join(packageDirectory.path, package.id));
    if (await directory.exists()) await directory.delete(recursive: true);
    await registry.remove(package.id);
  }
}

class UninstallManager {
  const UninstallManager(this.installer);
  final PackageInstaller installer;

  Future<void> uninstall(InstalledPackage package) => installer.uninstall(package);
}

class DependencyManager {
  const DependencyManager();

  List<String> missingDependencies(MarketPackage package, PackageRegistry registry) =>
      package.dependencies.where((dependency) => !registry.contains(dependency)).toList(growable: false);
}

class UpdateManager {
  const UpdateManager();

  bool hasUpdate(MarketPackage package, InstalledPackage? installed) =>
      installed != null && _compareVersions(package.version, installed.version) > 0;
}

int _compareVersions(String left, String right) {
  List<int> parts(String version) => version.split(RegExp(r'[.+_-]')).map((part) => int.tryParse(part) ?? 0).toList();
  final a = parts(left);
  final b = parts(right);
  for (var index = 0; index < (a.length > b.length ? a.length : b.length); index++) {
    final first = index < a.length ? a[index] : 0;
    final second = index < b.length ? b[index] : 0;
    if (first != second) return first.compareTo(second);
  }
  return 0;
}

abstract interface class MarketCatalogSource {
  String get id;
  Future<List<MarketPackage>> loadCatalog();
}

class MarketSourceConfig {
  const MarketSourceConfig({required this.id, required this.catalogUri, required this.trustedDownloadHosts});
  final String id;
  final Uri catalogUri;
  final Set<String> trustedDownloadHosts;

  bool get isValid => catalogUri.scheme == 'https' &&
      catalogUri.userInfo.isEmpty &&
      catalogUri.host.isNotEmpty &&
      trustedDownloadHosts.isNotEmpty &&
      trustedDownloadHosts.every((host) => RegExp(r'^[a-z0-9.-]+$').hasMatch(host.toLowerCase()));
}

const maxMarketPackageBytes = 50 * 1024 * 1024;

class MarketPackageManager extends ChangeNotifier {
  MarketPackageManager({
    required List<MarketPackage> catalog,
    required this.environment,
    required PackageDownloader downloader,
    Future<Directory> Function()? supportDirectoryProvider,
    PackageSignatureVerifier? signatureVerifier,
    this.maxPackageBytes = maxMarketPackageBytes,
    this.timeout = const Duration(seconds: 30),
  })  : _catalog = _validateCatalog(catalog),
        _downloadManager = PackageDownloadManager(downloader),
        _supportDirectoryProvider = supportDirectoryProvider ?? getApplicationSupportDirectory,
        _verifier = PackageVerifier(signatureVerifier: signatureVerifier);

  factory MarketPackageManager.bundled({Set<String> trustedDownloadHosts = const {}}) => MarketPackageManager(
        catalog: bundledMarketCatalog,
        environment: const CompatibilityEnvironment(platform: 'Android'),
        downloader: BundledAndHttpPackageDownloader(trustedDownloadHosts: trustedDownloadHosts),
      );

  final CompatibilityEnvironment environment;
  final PackageDownloadManager _downloadManager;
  final Future<Directory> Function() _supportDirectoryProvider;
  final PackageVerifier _verifier;
  final int maxPackageBytes;
  final Duration timeout;
  List<MarketPackage> _catalog;
  final Map<String, PackageStatus> _transientStatus = {};
  final Map<String, String> _errors = {};
  final Set<String> _busy = {};
  Future<void>? _initializing;
  PackageRegistry? _registry;
  PackageInstaller? _installer;
  UninstallManager? _uninstallManager;

  List<MarketPackage> get catalog => List.unmodifiable(_catalog);
  List<InstalledPackage> get installedPackages => _registry?.installed ?? const [];
  String? errorFor(String id) => _errors[id];
  InstalledPackage? installedById(String id) => _registry?.byId(id);

  Future<void> initialize() async {
    final registry = _registry;
    if (registry != null) return;
    final current = _initializing;
    if (current != null) return current;
    final future = _initialize();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    final support = await _supportDirectoryProvider();
    final packageDirectory = Directory(p.join(support.path, 'market_packages'));
    await packageDirectory.create(recursive: true);
    final registry = PackageRegistry(File(p.join(packageDirectory.path, 'registry.json')));
    await registry.load();
    _registry = registry;
    final installer = PackageInstaller(packageDirectory: packageDirectory, registry: registry);
    _installer = installer;
    _uninstallManager = UninstallManager(installer);
    notifyListeners();
  }

  PackageCompatibilityResult compatibilityFor(MarketPackage package) {
    // Actual environment (including ABI and runtime availability) is used by installation and UI status.
    final result = CompatibilityChecker(environment).check(package);
    if (result.status != PackageCompatibility.compatible) return result;
    if (_registry == null && package.dependencies.isNotEmpty) {
      return const PackageCompatibilityResult(PackageCompatibility.incompatible, ['Package registry is not initialized.']);
    }
    final missing = _registry == null ? const <String>[] : const DependencyManager().missingDependencies(package, _registry!);
    if (missing.isNotEmpty) {
      return PackageCompatibilityResult(PackageCompatibility.incompatible, ['Missing dependencies: ${missing.join(', ')}.']);
    }
    return result;
  }

  PackageStatus statusFor(MarketPackage package) {
    if (_busy.contains(package.id)) return _transientStatus[package.id] ?? PackageStatus.downloading;
    final explicit = _transientStatus[package.id];
    if (explicit == PackageStatus.failed) return PackageStatus.failed;
    if (package.isBundledCore) return PackageStatus.installed;
    final compatibility = compatibilityFor(package).status;
    if (compatibility != PackageCompatibility.compatible ||
        (package.downloadSizeBytes != null && package.downloadSizeBytes! > maxPackageBytes)) {
      return PackageStatus.incompatible;
    }
    if (explicit == PackageStatus.incompatible) {
      _transientStatus.remove(package.id);
      _errors.remove(package.id);
    }
    final installed = _registry?.byId(package.id);
    if (installed != null) return const UpdateManager().hasUpdate(package, installed) ? PackageStatus.updateAvailable : PackageStatus.installed;
    return explicit ?? PackageStatus.available;
  }

  bool canInstall(MarketPackage package) {
    if (_busy.contains(package.id) || package.isBundledCore || !package.hasArtifact || !package.canBeInstalledAsData) return false;
    if (compatibilityFor(package).status != PackageCompatibility.compatible) return false;
    if (package.dependencies.isNotEmpty && _registry == null) return false;
    return _registry == null || const DependencyManager().missingDependencies(package, _registry!).isEmpty;
  }

  Future<InstalledPackage> install(MarketPackage package, {required bool licenseAccepted}) async {
    if (!licenseAccepted) throw const PackageManagerException('Accept the package license before installation.');
    if (_busy.contains(package.id)) throw const PackageManagerException('This package already has an active operation.');
    await initialize();
    if (!_catalog.any((entry) => identical(entry, package))) {
      throw const PackageManagerException('Package is not a canonical entry in the active trusted catalog.');
    }
    if (package.downloadSizeBytes != null && package.downloadSizeBytes! > maxPackageBytes) {
      _setStatus(package.id, PackageStatus.incompatible, 'Package exceeds the configured size limit.');
      throw const PackageManagerException('Package exceeds the configured size limit.');
    }
    final compatibility = compatibilityFor(package);
    if (compatibility.status != PackageCompatibility.compatible) {
      _setStatus(package.id, PackageStatus.incompatible, compatibility.reasons.join(' '));
      throw PackageManagerException(compatibility.reasons.isEmpty ? 'Package is incompatible.' : compatibility.reasons.join(' '));
    }
    if (!package.canBeInstalledAsData) {
      _setStatus(package.id, PackageStatus.incompatible, 'Executable/archive package loading is not supported.');
      throw const PackageManagerException('Executable or archive packages are not loaded by this app.');
    }
    if (!package.hasArtifact) throw const PackageManagerException('This catalog entry has no published package artifact yet.');
    final missing = const DependencyManager().missingDependencies(package, _registry!);
    if (missing.isNotEmpty) {
      _setStatus(package.id, PackageStatus.incompatible, 'Missing dependencies: ${missing.join(', ')}.');
      throw PackageManagerException('Missing package dependencies: ${missing.join(', ')}.');
    }
    final current = _registry!.byId(package.id);
    if (current?.version == package.version) {
      _setStatus(package.id, PackageStatus.installed, null);
      return current!;
    }

    _busy.add(package.id);
    _setStatus(package.id, PackageStatus.downloading, null);
    try {
      final maxBytes = maxPackageBytes < 0 ? 0 : maxPackageBytes;
      final downloaded = await _downloadManager.download(package, maxBytes: maxBytes, timeout: timeout);
      _setStatus(package.id, PackageStatus.downloaded, null);
      _setStatus(package.id, PackageStatus.verifying, null);
      final verified = await _verifier.verify(package, downloaded.bytes);
      final installer = _installer;
      if (installer == null) throw const PackageManagerException('Package registry is not initialized.');
      final installed = await installer.install(verified);
      _setStatus(package.id, PackageStatus.installed, null);
      return installed;
    } on Exception catch (error) {
      final message = error is PackageManagerException ? error.message : 'Package operation failed safely.';
      _setStatus(package.id, PackageStatus.failed, message);
      rethrow;
    } finally {
      _busy.remove(package.id);
      notifyListeners();
    }
  }

  Future<void> uninstall(String id) async {
    await initialize();
    if (_busy.contains(id)) throw const PackageManagerException('This package already has an active operation.');
    final installed = _registry!.byId(id);
    if (installed == null) return;
    _busy.add(id);
    try {
      await _uninstallManager!.uninstall(installed);
      _setStatus(id, PackageStatus.available, null);
    } on Exception {
      _setStatus(id, PackageStatus.failed, 'Package uninstall failed safely.');
      rethrow;
    } finally {
      _busy.remove(id);
      notifyListeners();
    }
  }

  void replaceCatalog(List<MarketPackage> packages) {
    _catalog = _validateCatalog(packages);
    _transientStatus.removeWhere((id, status) => status == PackageStatus.failed || status == PackageStatus.incompatible);
    notifyListeners();
  }

  Future<void> refreshCatalog(MarketCatalogSource source) async {
    final packages = await source.loadCatalog().timeout(timeout);
    replaceCatalog(packages);
  }

  void _setStatus(String id, PackageStatus status, String? error) {
    _transientStatus[id] = status;
    if (error == null) {
      _errors.remove(id);
    } else {
      _errors[id] = error;
    }
    notifyListeners();
  }

  static List<MarketPackage> _validateCatalog(List<MarketPackage> packages) {
    final ids = <String>{};
    for (final package in packages) {
      if (!_isSafePackageId(package.id) || !_isSafeVersion(package.version) || !ids.add(package.id)) {
        throw const PackageManagerException('Market catalog contains an invalid or duplicate package ID/version.');
      }
      if (package.officialSourceUri.scheme != 'https' || package.officialSourceUri.userInfo.isNotEmpty) {
        throw const PackageManagerException('Market catalog entries must provide an HTTPS official source.');
      }
      if (package.downloadSizeBytes != null && package.downloadSizeBytes! < 0) {
        throw const PackageManagerException('Market catalog contains a negative package size.');
      }
    }
    return List.unmodifiable(packages);
  }
}

typedef HostResolver = Future<List<InternetAddress>> Function(String host);

final bundledMarketCatalog = <MarketPackage>[
  MarketPackage(
    id: 'tool.dns-lookup',
    name: 'DNS Lookup',
    description: 'Built-in, passive A/AAAA lookup through the Android system resolver.',
    category: MarketCategory.securityTools,
    version: '1.0.0',
    downloadSizeBytes: 0,
    officialSource: 'Cybersecurity Assistant core',
    officialSourceUri: Uri(scheme: 'https', host: 'github.com', path: '/wnr-code/CYBERSECURITY-ASSISTANT'),
    license: 'Project license',
    platforms: ['Android'],
    architectures: ['any'],
    dependencies: [],
    runtimeRequirements: [],
    permissions: [],
    compatibility: PackageCompatibility.compatible,
    installationGuide: 'Already included in the core app and registered in Tool Registry.',
    payloadType: PackagePayloadType.jsonData,
    isBundledCore: true,
  ),
  MarketPackage(
    id: 'runtime.embedded',
    name: 'Embedded Runtime (planned)',
    description: 'Catalog metadata only. Runtime execution is not implemented or bundled.',
    category: MarketCategory.runtime,
    version: '0.0.0',
    downloadSizeBytes: null,
    officialSource: 'Not published',
    officialSourceUri: Uri(scheme: 'https', host: 'github.com', path: '/wnr-code/CYBERSECURITY-ASSISTANT'),
    license: 'Not published',
    platforms: ['Android'],
    architectures: ['arm64-v8a', 'x86_64'],
    dependencies: [],
    runtimeRequirements: [],
    permissions: [],
    compatibility: PackageCompatibility.unsupported,
    installationGuide: 'Runtime package is a roadmap placeholder. No runtime or downloaded code can be executed.',
    payloadType: PackagePayloadType.nativeExecutable,
  ),
  MarketPackage(
    id: 'plugin.sample',
    name: 'Sample Plugin (planned)',
    description: 'Metadata preview only; plugin execution requires a future reviewed runtime and adapter.',
    category: MarketCategory.plugins,
    version: '0.0.0',
    downloadSizeBytes: null,
    officialSource: 'Not published',
    officialSourceUri: Uri(scheme: 'https', host: 'github.com', path: '/wnr-code/CYBERSECURITY-ASSISTANT'),
    license: 'Not published',
    platforms: ['Android'],
    architectures: ['any'],
    dependencies: [],
    runtimeRequirements: ['embedded-runtime'],
    permissions: [],
    compatibility: PackageCompatibility.incompatible,
    installationGuide: 'No package artifact is published. This entry cannot be installed or executed.',
    payloadType: PackagePayloadType.opaqueData,
  ),
  MarketPackage(
    id: 'model.local-small',
    name: 'Local AI Model (planned)',
    description: 'Large model metadata preview. Model download and inference are not implemented.',
    category: MarketCategory.aiModels,
    version: '0.0.0',
    downloadSizeBytes: null,
    officialSource: 'Not published',
    officialSourceUri: Uri(scheme: 'https', host: 'github.com', path: '/wnr-code/CYBERSECURITY-ASSISTANT'),
    license: 'Not published',
    platforms: ['Android'],
    architectures: ['arm64-v8a'],
    dependencies: [],
    runtimeRequirements: ['local-model-runtime'],
    permissions: [],
    compatibility: PackageCompatibility.limitedCompatibility,
    installationGuide: 'Inference runtime and model verification keys are not yet available.',
    payloadType: PackagePayloadType.opaqueData,
  ),
  MarketPackage(
    id: 'knowledge.security-baseline',
    name: 'Security Assessment Evidence Guide',
    description: 'A small, offline knowledge pack describing evidence confidence and safe authorized checks.',
    category: MarketCategory.knowledgePacks,
    version: '1.0.0',
    downloadSizeBytes: 731,
    officialSource: 'Cybersecurity Assistant example package',
    officialSourceUri: Uri(scheme: 'https', host: 'github.com', path: '/wnr-code/CYBERSECURITY-ASSISTANT'),
    license: 'CC BY-SA 4.0',
    platforms: ['Android'],
    architectures: ['any'],
    dependencies: [],
    runtimeRequirements: [],
    permissions: [],
    compatibility: PackageCompatibility.compatible,
    installationGuide: 'Accept the license, then install. The JSON manifest is checksum-verified and stored as data only.',
    payloadType: PackagePayloadType.jsonData,
    sha256: 'afbfc2c4b27775bfba5a7faedaec3f84571123db2fc142c9492f17e52f5637e5',
    bundledAssetPath: 'assets/market/knowledge_baseline_1_0_0.json',
  ),
  MarketPackage(
    id: 'connector.byoi-guide',
    name: 'BYOI / BYOK Connector Guide',
    description: 'Catalog preview for optional user-owned cloud/API connections; no connector code or secrets included.',
    category: MarketCategory.cloudApiConnectors,
    version: '0.1.0',
    downloadSizeBytes: null,
    officialSource: 'Cybersecurity Assistant core',
    officialSourceUri: Uri(scheme: 'https', host: 'github.com', path: '/wnr-code/CYBERSECURITY-ASSISTANT'),
    license: 'Project license',
    platforms: ['Android'],
    architectures: ['any'],
    dependencies: [],
    runtimeRequirements: [],
    permissions: [],
    compatibility: PackageCompatibility.limitedCompatibility,
    installationGuide: 'Connector adapters are not implemented. Configure only your own provider and never embed developer credentials.',
    payloadType: PackagePayloadType.opaqueData,
  ),
];
