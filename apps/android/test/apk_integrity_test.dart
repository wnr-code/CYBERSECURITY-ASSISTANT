import 'package:crypto/crypto.dart';
import 'package:cybersecurity_assistant/core/apk_integrity.dart';
import 'package:cybersecurity_assistant/core/secure_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIntegrityBridge implements NativeAppIntegrityBridge {
  Map<String, Object?>? identity;

  @override
  Future<Map<String, Object?>?> readInstalledIdentity() async => identity;
}

class _MemorySecureStorage implements SecureStorageBackend {
  final values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

const _signer = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _apkA = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _apkB = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

Map<String, Object?> _identity({
  int version = 1,
  String signer = _signer,
  String digest = _apkA,
  String installer = 'com.android.vending',
  bool configured = true,
  bool trusted = true,
}) => {
      'status': configured && trusted ? 'trusted' : configured ? 'untrusted' : 'unconfigured',
      'packageName': 'org.cybersecurityassistant.cybersecurity_assistant',
      'versionCode': version,
      'signerSha256': signer,
      'signerPinConfigured': configured,
      'trustedSigner': trusted,
      'installedComponentsSha256': digest,
      'installerPackageName': installer,
    };

void main() {
  late _FakeIntegrityBridge bridge;
  late _MemorySecureStorage storage;
  late ApkIntegrityMonitor monitor;

  setUp(() {
    bridge = _FakeIntegrityBridge()..identity = _identity();
    storage = _MemorySecureStorage();
    monitor = ApkIntegrityMonitor(nativeBridge: bridge, secureStorage: storage);
  });

  test('first trusted Play installation anchors package, certificate, version, and APK digest', () async {
    final result = await monitor.verifyAtStartup(enforceRelease: true);
    expect(result.state, ApkIntegrityState.verified);
    expect(result.packageName, 'org.cybersecurityassistant.cybersecurity_assistant');
    expect(result.installerPackageName, 'com.android.vending');
    expect(storage.values, hasLength(1));
    expect(storage.values.values.single, contains(_apkA));
  });

  test('fails closed when signer pin is absent, signer is unknown, or native identity is unavailable', () async {
    bridge.identity = _identity(configured: false, trusted: false);
    expect((await monitor.verifyAtStartup(enforceRelease: true)).state, ApkIntegrityState.unconfigured);
    bridge.identity = _identity(trusted: false);
    expect((await monitor.verifyAtStartup(enforceRelease: true)).state, ApkIntegrityState.untrusted);
    bridge.identity = null;
    expect((await monitor.verifyAtStartup(enforceRelease: true)).state, ApkIntegrityState.unavailable);
  });

  test('detects modified APK bytes at the same version', () async {
    expect((await monitor.verifyAtStartup(enforceRelease: true)).trusted, isTrue);
    bridge.identity = _identity(digest: _apkB);
    final result = await monitor.verifyAtStartup(enforceRelease: true);
    expect(result.state, ApkIntegrityState.untrusted);
    expect(result.message, 'Installed APK contents changed without a version update.');
  });

  test('rejects downgrade, certificate substitution, and non-Play update source', () async {
    bridge.identity = _identity(version: 2);
    await monitor.verifyAtStartup(enforceRelease: true);
    bridge.identity = _identity(version: 1);
    expect((await monitor.verifyAtStartup(enforceRelease: true)).message, 'APK downgrade was detected.');
    bridge.identity = _identity(version: 2, signer: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd', trusted: false);
    expect((await monitor.verifyAtStartup(enforceRelease: true)).message, 'APK signing certificate is not trusted.');
    bridge.identity = _identity(version: 3, installer: 'com.android.packageinstaller');
    expect((await monitor.verifyAtStartup(enforceRelease: true)).message, 'Production APK must be installed or updated by Google Play.');
    bridge.identity = _identity(version: 2);
    expect((await monitor.verifyAtStartup(enforceRelease: true)).trusted, isTrue);
  });

  test('accepts only a higher-version same-signer Play update and refreshes digest baseline', () async {
    await monitor.verifyAtStartup(enforceRelease: true);
    bridge.identity = _identity(version: 2, digest: _apkB);
    final result = await monitor.verifyAtStartup(enforceRelease: true);
    expect(result.trusted, isTrue);
    expect(storage.values.values.single, contains(_apkB));
  });

  test('candidate metadata rejects package mismatch, unknown signer, downgrade, and checksum tampering', () {
    final bytes = [1, 2, 3, 4];
    final digest = sha256.convert(bytes).toString();
    bool verify({
      String packageName = 'org.cybersecurityassistant.cybersecurity_assistant',
      int version = 2,
      String signer = _signer,
      String checksum = '',
      List<int>? payload,
    }) => ApkIntegrityMonitor.verifyCandidateMetadataAndBytes(
          installedPackageName: 'org.cybersecurityassistant.cybersecurity_assistant',
          installedVersionCode: 1,
          trustedSignerSha256: _signer,
          candidatePackageName: packageName,
          candidateVersionCode: version,
          candidateSignerSha256: signer,
          expectedArtifactSha256: checksum.isEmpty ? digest : checksum,
          artifactBytes: payload ?? bytes,
        );

    expect(verify(), isTrue);
    expect(verify(packageName: 'org.other.app'), isFalse);
    expect(verify(version: 1), isFalse);
    expect(verify(signer: 'e' * 64), isFalse);
    expect(verify(payload: [9, 9]), isFalse);
    expect(verify(checksum: 'invalid'), isFalse);
  });
}
