import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cybersecurity_assistant/core/package_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixtureDownloader implements PackageDownloader {
  _FixtureDownloader(this.bytes);
  Uint8List bytes;
  int calls = 0;
  bool fail = false;

  @override
  Future<DownloadedPackage> download(MarketPackage package, {required int maxBytes, required Duration timeout}) async {
    calls++;
    if (fail) throw const PackageManagerException('Fixture download failed.');
    return DownloadedPackage(Uint8List.fromList(bytes));
  }
}

Uint8List _manifestBytes(String id, String version) => Uint8List.fromList(utf8.encode(jsonEncode({
      'schemaVersion': 1,
      'packageId': id,
      'version': version,
      'content': {'title': 'Safe fixture data', 'entries': []},
    })));

MarketPackage _fixturePackage({
  String id = 'knowledge.fixture',
  String version = '1.0.0',
  String? checksum,
  List<String> dependencies = const [],
  List<String> runtimes = const [],
  PackageCompatibility compatibility = PackageCompatibility.compatible,
  PackagePayloadType payloadType = PackagePayloadType.jsonData,
  Uint8List? payload,
}) {
  final bytes = payload ?? _manifestBytes(id, version);
  return MarketPackage(
    id: id,
    name: 'Fixture Knowledge Pack',
    description: 'Non-executable package fixture used by tests.',
    category: MarketCategory.knowledgePacks,
    version: version,
    downloadSizeBytes: bytes.length,
    officialSource: 'Test fixture; no network access',
    officialSourceUri: Uri.https('github.com', '/fixture/market'),
    license: 'CC0-1.0',
    platforms: const ['Android'],
    architectures: const ['any'],
    dependencies: dependencies,
    runtimeRequirements: runtimes,
    permissions: const [],
    compatibility: compatibility,
    installationGuide: 'Verify and store as data; never execute.',
    payloadType: payloadType,
    sha256: checksum ?? sha256.convert(bytes).toString(),
    downloadUri: Uri.https('packages.example.test', '/fixture/$id-$version.json'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Market runtime integration', () {
    test('bundled tool metadata follows registered runtime availability and executable Market runtimes stay unsupported', () {
      final manager = MarketPackageManager.bundled();
      final tool = bundledMarketCatalog.firstWhere((package) => package.id == 'tool.dns-lookup');
      final external = bundledMarketCatalog.firstWhere((package) => package.id == 'runtime.embedded');
      expect(manager.statusFor(tool), PackageStatus.incompatible);
      expect(manager.canInstall(external), isFalse);
      manager.updateAvailableRuntimes(const {'runtime.dart.security-tools'});
      expect(manager.statusFor(tool), PackageStatus.installed);
      expect(manager.statusFor(external), PackageStatus.incompatible);
      manager.dispose();
    });
  });

  group('Market catalog', () {
    test('blocks untrusted hosts and private DNS answers before package HTTP requests', () async {
      var resolutions = 0;
      var clientsCreated = 0;
      final package = _fixturePackage();
      final untrustedDownloader = BundledAndHttpPackageDownloader(
        trustedDownloadHosts: const {'official.example'},
        hostResolver: (_) async {
          resolutions++;
          return [InternetAddress('8.8.8.8')];
        },
        httpClientFactory: () {
          clientsCreated++;
          return HttpClient();
        },
      );
      await expectLater(
        untrustedDownloader.download(package, maxBytes: 1024, timeout: const Duration(seconds: 1)),
        throwsA(isA<PackageManagerException>()),
      );
      expect(resolutions, 0);
      expect(clientsCreated, 0);

      final privateAddressDownloader = BundledAndHttpPackageDownloader(
        trustedDownloadHosts: const {'packages.example.test'},
        hostResolver: (_) async => [InternetAddress('127.0.0.1')],
        httpClientFactory: () {
          clientsCreated++;
          return HttpClient();
        },
      );
      await expectLater(
        privateAddressDownloader.download(package, maxBytes: 1024, timeout: const Duration(seconds: 1)),
        throwsA(isA<PackageManagerException>()),
      );
      expect(clientsCreated, 0);
    });

    test('declares all six categories and exposes a small safe catalog', () {
      expect(MarketCategory.values, hasLength(6));
      expect(bundledMarketCatalog, hasLength(6));
      expect(bundledMarketCatalog.map((package) => package.category).toSet(), containsAll(MarketCategory.values));
      final sample = bundledMarketCatalog.singleWhere((package) => package.id == 'knowledge.security-baseline');
      expect(sample.hasArtifact, isTrue);
      expect(sample.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(bundledMarketCatalog.where((package) => package.category == MarketCategory.plugins).single.compatibility,
          PackageCompatibility.incompatible);
    });

    test('requires HTTPS and user-configured hosts for external sources', () {
      expect(MarketSourceConfig(
        id: 'user-source',
        catalogUri: Uri.https('catalog.example.test', '/market.json'),
        trustedDownloadHosts: const {'packages.example.test'},
      ).isValid, isTrue);
      expect(MarketSourceConfig(
        id: 'unsafe-source',
        catalogUri: Uri.parse('http://catalog.example.test/market.json'),
        trustedDownloadHosts: const {'packages.example.test'},
      ).isValid, isFalse);
    });
  });

  group('Package Manager fixture flow', () {
    late Directory supportDirectory;

    setUp(() async {
      supportDirectory = await Directory.systemTemp.createTemp('market-package-test-');
    });

    tearDown(() async {
      if (await supportDirectory.exists()) await supportDirectory.delete(recursive: true);
    });

    MarketPackageManager managerFor(List<MarketPackage> catalog, PackageDownloader downloader) => MarketPackageManager(
          catalog: catalog,
          environment: const CompatibilityEnvironment(platform: 'Android', architecture: 'arm64-v8a'),
          downloader: downloader,
          supportDirectoryProvider: () async => supportDirectory,
        );

    test('installs the bundled Market example through the real offline asset source', () async {
      final package = bundledMarketCatalog.singleWhere((entry) => entry.id == 'knowledge.security-baseline');
      final manager = managerFor([package], BundledAndHttpPackageDownloader());
      await manager.initialize();
      final installed = await manager.install(package, licenseAccepted: true);
      final file = File('${supportDirectory.path}/market_packages/${installed.relativeFile}');
      expect(manager.statusFor(package), PackageStatus.installed);
      expect(installed.sha256, package.sha256);
      expect(await file.readAsString(), contains('evidence-confidence'));
      expect(await file.readAsString(), contains('potential or informational indicator'));
      manager.dispose();
    });

    test('downloads a fixture, verifies checksum, installs data, and reloads the registry', () async {
      final bytes = _manifestBytes('knowledge.fixture', '1.0.0');
      final package = _fixturePackage(payload: bytes);
      final downloader = _FixtureDownloader(bytes);
      final manager = managerFor([package], downloader);
      final observedStatuses = <PackageStatus>[];
      manager.addListener(() => observedStatuses.add(manager.statusFor(package)));

      await manager.initialize();
      expect(manager.statusFor(package), PackageStatus.available);
      expect(manager.canInstall(package), isTrue);
      final installed = await manager.install(package, licenseAccepted: true);

      expect(downloader.calls, 1);
      expect(manager.statusFor(package), PackageStatus.installed);
      expect(observedStatuses, containsAll([
        PackageStatus.downloading,
        PackageStatus.downloaded,
        PackageStatus.verifying,
        PackageStatus.installed,
      ]));
      final payload = File('${supportDirectory.path}/market_packages/${installed.relativeFile}');
      expect(await payload.exists(), isTrue);
      expect(await payload.readAsString(), utf8.decode(bytes));
      expect(await payload.readAsString(), isNot(contains('script')));

      final restored = managerFor([package], _FixtureDownloader(bytes));
      await restored.initialize();
      expect(restored.statusFor(package), PackageStatus.installed);
      expect(restored.installedById(package.id)?.sha256, installed.sha256);
      manager.dispose();
      restored.dispose();
    });

    test('checksum mismatch fails closed and does not install a package', () async {
      final bytes = _manifestBytes('knowledge.fixture', '1.0.0');
      final package = _fixturePackage(payload: bytes, checksum: List.filled(64, '0').join());
      final manager = managerFor([package], _FixtureDownloader(bytes));
      await manager.initialize();

      await expectLater(
        manager.install(package, licenseAccepted: true),
        throwsA(isA<PackageManagerException>()),
      );
      expect(manager.statusFor(package), PackageStatus.failed);
      expect(manager.errorFor(package.id), contains('checksum'));
      expect(manager.installedById(package.id), isNull);
      expect(await Directory('${supportDirectory.path}/market_packages/${package.id}').exists(), isFalse);
      manager.dispose();
    });

    test('missing dependencies prevent the download and mark the package incompatible', () async {
      final bytes = _manifestBytes('knowledge.fixture', '1.0.0');
      final package = _fixturePackage(payload: bytes, dependencies: const ['dependency.not-installed']);
      final downloader = _FixtureDownloader(bytes);
      final manager = managerFor([package], downloader);
      await manager.initialize();

      expect(manager.statusFor(package), PackageStatus.incompatible);
      expect(manager.canInstall(package), isFalse);
      await expectLater(
        manager.install(package, licenseAccepted: true),
        throwsA(isA<PackageManagerException>()),
      );
      expect(downloader.calls, 0);
      expect(manager.errorFor(package.id), contains('dependency.not-installed'));
      manager.dispose();
    });

    test('optional signatures require a configured verifier', () async {
      final bytes = _manifestBytes('knowledge.fixture', '1.0.0');
      final package = MarketPackage(
        id: 'knowledge.fixture',
        name: 'Signed fixture',
        description: 'Signature rejection fixture.',
        category: MarketCategory.knowledgePacks,
        version: '1.0.0',
        downloadSizeBytes: bytes.length,
        officialSource: 'Test fixture',
        officialSourceUri: Uri.https('github.com', '/fixture/market'),
        license: 'CC0-1.0',
        platforms: const ['Android'],
        architectures: const ['any'],
        dependencies: const [],
        runtimeRequirements: const [],
        permissions: const [],
        compatibility: PackageCompatibility.compatible,
        installationGuide: 'Fixture only.',
        payloadType: PackagePayloadType.jsonData,
        sha256: sha256.convert(bytes).toString(),
        signature: 'Zml4dHVyZS1zaWduYXR1cmU=',
        downloadUri: Uri.https('packages.example.test', '/fixture/signed.json'),
      );
      final manager = managerFor([package], _FixtureDownloader(bytes));
      await manager.initialize();
      await expectLater(manager.install(package, licenseAccepted: true), throwsA(isA<PackageManagerException>()));
      expect(manager.errorFor(package.id), contains('signature'));
      expect(manager.installedById(package.id), isNull);
      manager.dispose();
    });

    test('license must be accepted before any package download', () async {
      final bytes = _manifestBytes('knowledge.fixture', '1.0.0');
      final package = _fixturePackage(payload: bytes);
      final downloader = _FixtureDownloader(bytes);
      final manager = managerFor([package], downloader);
      await expectLater(
        manager.install(package, licenseAccepted: false),
        throwsA(isA<PackageManagerException>()),
      );
      expect(downloader.calls, 0);
      manager.dispose();
    });

    test('metadata mismatch and executable payloads are rejected', () async {
      final mismatched = Uint8List.fromList(utf8.encode('{"schemaVersion":1,"packageId":"wrong.id","version":"1.0.0","content":{}}'));
      final package = _fixturePackage(payload: mismatched);
      final manager = managerFor([package], _FixtureDownloader(mismatched));
      await manager.initialize();
      await expectLater(manager.install(package, licenseAccepted: true), throwsA(isA<PackageManagerException>()));
      expect(manager.installedById(package.id), isNull);
      manager.dispose();

      final executableBytes = Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46]);
      final executable = _fixturePackage(
        id: 'tool.untrusted-binary',
        payload: executableBytes,
        payloadType: PackagePayloadType.nativeExecutable,
      );
      final executableManager = managerFor([executable], _FixtureDownloader(executableBytes));
      await executableManager.initialize();
      await expectLater(
        executableManager.install(executable, licenseAccepted: true),
        throwsA(isA<PackageManagerException>()),
      );
      expect(executableManager.installedById(executable.id), isNull);
      executableManager.dispose();
    });

    test('updates replace old data atomically and uninstall removes files and registry entries', () async {
      final v1Bytes = _manifestBytes('knowledge.fixture', '1.0.0');
      final v1 = _fixturePackage(payload: v1Bytes);
      final downloader = _FixtureDownloader(v1Bytes);
      final manager = managerFor([v1], downloader);
      await manager.initialize();
      final installedV1 = await manager.install(v1, licenseAccepted: true);
      final v2Bytes = _manifestBytes('knowledge.fixture', '1.1.0');
      final v2 = _fixturePackage(version: '1.1.0', payload: v2Bytes);
      downloader.bytes = v2Bytes;
      manager.replaceCatalog([v2]);

      expect(manager.statusFor(v2), PackageStatus.updateAvailable);
      final installedV2 = await manager.install(v2, licenseAccepted: true);
      expect(installedV2.version, '1.1.0');
      expect(manager.statusFor(v2), PackageStatus.installed);
      expect(await File('${supportDirectory.path}/market_packages/${installedV1.relativeFile}').exists(), isFalse);
      expect(await File('${supportDirectory.path}/market_packages/${installedV2.relativeFile}').exists(), isTrue);

      await manager.uninstall(v2.id);
      expect(manager.statusFor(v2), PackageStatus.available);
      expect(manager.installedById(v2.id), isNull);
      expect(await Directory('${supportDirectory.path}/market_packages/${v2.id}').exists(), isFalse);
      manager.dispose();
    });

    test('download failures are reported and never register an installation', () async {
      final bytes = _manifestBytes('knowledge.fixture', '1.0.0');
      final package = _fixturePackage(payload: bytes);
      final downloader = _FixtureDownloader(bytes)..fail = true;
      final manager = managerFor([package], downloader);
      await manager.initialize();
      await expectLater(manager.install(package, licenseAccepted: true), throwsA(isA<PackageManagerException>()));
      expect(manager.statusFor(package), PackageStatus.failed);
      expect(manager.installedById(package.id), isNull);
      manager.dispose();
    });
  });
}
