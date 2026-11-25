import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'secure_credential_store.dart';

abstract interface class NativeAppIntegrityBridge {
  Future<Map<String, Object?>?> readInstalledIdentity();
}

class MethodChannelAppIntegrityBridge implements NativeAppIntegrityBridge {
  const MethodChannelAppIntegrityBridge({this.channel = const MethodChannel('org.cybersecurityassistant/app_integrity')});

  final MethodChannel channel;

  @override
  Future<Map<String, Object?>?> readInstalledIdentity() => channel.invokeMapMethod<String, Object?>('getInstalledIdentity');
}

enum ApkIntegrityState { verified, unconfigured, untrusted, unavailable }

class ApkIntegrityReport {
  const ApkIntegrityReport({required this.state, required this.message, this.packageName, this.versionCode, this.signerSha256, this.installedComponentsSha256, this.installerPackageName});

  final ApkIntegrityState state;
  final String message;
  final String? packageName;
  final int? versionCode;
  final String? signerSha256;
  final String? installedComponentsSha256;
  final String? installerPackageName;

  bool get trusted => state == ApkIntegrityState.verified;
}

/// Verifies native signing identity and anchors the installed APK digest in
/// Android Keystore-backed secure storage. Updates are accepted only after the
/// OS-installed package reports the trusted signer, a higher version, and the
/// official Play Store installer. This does not download or install APK files.
class ApkIntegrityMonitor {
  const ApkIntegrityMonitor({
    required this.nativeBridge,
    required this.secureStorage,
    this.playStoreInstallerId = 'com.android.vending',
  });

  static const _baselineKey = 'cybersecurity_assistant.apk.integrity.baseline.v1';
  static final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  final NativeAppIntegrityBridge nativeBridge;
  final SecureStorageBackend secureStorage;
  final String playStoreInstallerId;

  Future<ApkIntegrityReport> verifyAtStartup({required bool enforceRelease}) async {
    try {
      final identity = await nativeBridge.readInstalledIdentity();
      if (identity == null) return _unavailable('Native APK identity verification is unavailable.');
      final packageName = identity['packageName'];
      final versionCode = identity['versionCode'];
      final signer = identity['signerSha256'];
      final apkDigest = identity['installedComponentsSha256'];
      final trustedSigner = identity['trustedSigner'] == true;
      final configured = identity['signerPinConfigured'] == true;
      final installer = identity['installerPackageName'];
      if (!configured) return _unconfigured('Trusted developer signing certificate is not configured.');
      if (packageName is! String || packageName.isEmpty ||
          versionCode is! int || versionCode <= 0 ||
          signer is! String || !_sha256Pattern.hasMatch(signer) ||
          apkDigest is! String || !_sha256Pattern.hasMatch(apkDigest) ||
          installer is! String) {
        return _untrusted('Installed APK identity or integrity metadata is invalid.');
      }
      if (!trustedSigner) return _untrusted('APK signing certificate is not trusted.');
      if (identity['status'] != 'trusted') return _untrusted('Native APK integrity verification did not report a trusted identity.');
      if (!enforceRelease) {
        return ApkIntegrityReport(
          state: ApkIntegrityState.verified,
          message: 'Native package signature and APK digest were read successfully (development build).',
          packageName: packageName,
          versionCode: versionCode,
          signerSha256: signer,
          installedComponentsSha256: apkDigest,
          installerPackageName: installer,
        );
      }
      if (installer != playStoreInstallerId) return _untrusted('Production APK must be installed or updated by Google Play.');

      final previousValue = await secureStorage.read(key: _baselineKey);
      if (previousValue == null) {
        await _writeBaseline(packageName, versionCode, signer, apkDigest);
      } else {
        final decoded = jsonDecode(previousValue);
        if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
          return _untrusted('Stored APK integrity baseline is invalid.');
        }
        final oldPackage = decoded['packageName'];
        final oldVersion = decoded['versionCode'];
        final oldSigner = decoded['signerSha256'];
        final oldDigest = decoded['installedComponentsSha256'];
        if (oldPackage != packageName ||
            oldVersion is! int || oldVersion <= 0 ||
            oldSigner is! String || !_sha256Pattern.hasMatch(oldSigner) ||
            oldDigest is! String || !_sha256Pattern.hasMatch(oldDigest)) {
          return _untrusted('Stored APK integrity baseline does not match this app.');
        }
        if (signer != oldSigner) return _untrusted('APK signing identity changed; a different developer certificate is not accepted.');
        if (versionCode < oldVersion) return _untrusted('APK downgrade was detected.');
        if (versionCode == oldVersion && apkDigest != oldDigest) return _untrusted('Installed APK contents changed without a version update.');
        if (versionCode > oldVersion) await _writeBaseline(packageName, versionCode, signer, apkDigest);
      }
      return ApkIntegrityReport(
        state: ApkIntegrityState.verified,
        message: 'APK signing identity, version, installer, and integrity baseline are trusted.',
        packageName: packageName,
        versionCode: versionCode,
        signerSha256: signer,
        installedComponentsSha256: apkDigest,
        installerPackageName: installer,
      );
    } on PlatformException {
      return _unavailable('Native APK integrity verification failed.');
    } on FormatException {
      return _untrusted('APK integrity baseline could not be decoded.');
    } catch (_) {
      // Keystore/storage failures and all unexpected errors deny release startup.
      return _unavailable('APK integrity verification could not be completed.');
    }
  }

  Future<void> _writeBaseline(String packageName, int versionCode, String signer, String apkDigest) => secureStorage.write(
        key: _baselineKey,
        value: jsonEncode({
          'schemaVersion': 1,
          'packageName': packageName,
          'versionCode': versionCode,
          'signerSha256': signer,
          'installedComponentsSha256': apkDigest,
        }),
      );

  static ApkIntegrityReport _unconfigured(String message) => ApkIntegrityReport(state: ApkIntegrityState.unconfigured, message: message);
  static ApkIntegrityReport _untrusted(String message) => ApkIntegrityReport(state: ApkIntegrityState.untrusted, message: message);
  static ApkIntegrityReport _unavailable(String message) => ApkIntegrityReport(state: ApkIntegrityState.unavailable, message: message);

  /// Checks field consistency and the downloaded-byte digest for regression
  /// tests/future policy use. [candidateSignerSha256] must come from a native,
  /// Android-verified package parser; this Dart helper does not authenticate an
  /// APK signature and is never an install or sideload authorization. Production
  /// installs remain exclusively under Android Package Manager / Google Play.
  static bool verifyCandidateMetadataAndBytes({
    required String installedPackageName,
    required int installedVersionCode,
    required String trustedSignerSha256,
    required String candidatePackageName,
    required int candidateVersionCode,
    required String candidateSignerSha256,
    required String expectedArtifactSha256,
    required List<int> artifactBytes,
  }) {
    if (installedPackageName.isEmpty || candidatePackageName != installedPackageName ||
        candidateVersionCode <= installedVersionCode ||
        !_sha256Pattern.hasMatch(trustedSignerSha256) ||
        !_sha256Pattern.hasMatch(candidateSignerSha256) ||
        candidateSignerSha256 != trustedSignerSha256 ||
        !_sha256Pattern.hasMatch(expectedArtifactSha256)) {
      return false;
    }
    return sha256.convert(artifactBytes).toString() == expectedArtifactSha256;
  }
}
